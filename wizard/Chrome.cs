using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

namespace RLMMSetup
{
    /// <summary>
    /// Classic setup-wizard frame: a white header with the page title (or a painted side banner on the first and last
    /// pages), the page area, and Back / Next / Cancel at the bottom. Layout is in 96-dpi units; WinForms scales it.
    /// </summary>
    class WizardChrome : Form
    {
        public const int W = 660, H = 480, HeaderH = 64, FooterH = 50, BannerW = 172;

        protected readonly Panel header, headerLine, footer, body, banner, pages;
        protected readonly Label title, subtitle, brand;
        protected readonly Button back, next, cancel;
        protected readonly PictureBox headerLogo;
        static Image logo;

        public static Image Logo
        {
            get
            {
                if (logo == null) using (var s = Payload.Open("logo.png")) logo = new Bitmap(Image.FromStream(s));
                return logo;
            }
        }

        public WizardChrome()
        {
            SuspendLayout();
            AutoScaleDimensions = new SizeF(96F, 96F);
            AutoScaleMode = AutoScaleMode.Dpi;
            Font = new Font("Segoe UI", 9F);
            Text = "RLMM Setup";
            ClientSize = new Size(W, H);
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            BackColor = SystemColors.Control;
            using (var s = Payload.Open("RLMM.ico")) Icon = new Icon(s);

            // header
            header = new Panel { Dock = DockStyle.Top, Height = HeaderH, BackColor = Color.White };
            title = new Label { AutoSize = true, Location = new Point(22, 12), Font = new Font("Segoe UI", 10.5F, FontStyle.Bold) };
            subtitle = new Label { AutoSize = false, Location = new Point(36, 35), Size = new Size(W - 36 - 70, 22), AutoEllipsis = true };
            headerLogo = new PictureBox { Image = Logo, SizeMode = PictureBoxSizeMode.Zoom, Size = new Size(44, 44), Location = new Point(W - 44 - 14, 10) };
            header.Controls.AddRange(new Control[] { title, subtitle, headerLogo });
            headerLine = new Panel { Dock = DockStyle.Top, Height = 1, BackColor = Color.FromArgb(214, 214, 214) };

            // footer
            footer = new Panel { Dock = DockStyle.Bottom, Height = FooterH };
            var footerLine = new Panel { Dock = DockStyle.Top, Height = 1, BackColor = Color.FromArgb(214, 214, 214) };
            brand = new Label { AutoSize = true, ForeColor = SystemColors.GrayText, Location = new Point(14, 18), Text = "RLMM Setup " + Program.Version };
            cancel = new Button { Text = "Cancel", Size = new Size(88, 27), Location = new Point(W - 14 - 88, 12) };
            next = new Button { Text = "&Next >", Size = new Size(88, 27), Location = new Point(W - 14 - 88 - 12 - 88, 12) };
            back = new Button { Text = "< &Back", Size = new Size(88, 27), Location = new Point(W - 14 - 88 - 12 - 88 - 88, 12) };
            footer.Controls.AddRange(new Control[] { footerLine, brand, back, next, cancel });
            AcceptButton = next;

            // body: optional banner on the left, pages on the right
            body = new Panel { Dock = DockStyle.Fill };
            banner = new BannerPanel { Dock = DockStyle.Left, Width = BannerW };
            pages = new Panel { Dock = DockStyle.Fill };
            body.Controls.Add(pages);
            body.Controls.Add(banner);

            Controls.Add(body);
            Controls.Add(headerLine);
            Controls.Add(header);
            Controls.Add(footer);
        }

        /// <summary>Call at the end of the derived constructor, after every page is built (so they get DPI scaling).</summary>
        protected void FinishLayout()
        {
            ResumeLayout(false);
            PerformLayout();
        }

        protected Panel NewPage(bool bannerStyle)
        {
            var p = new Panel { Dock = DockStyle.Fill, Visible = false, Tag = bannerStyle, Padding = bannerStyle ? new Padding(22, 20, 22, 8) : new Padding(26, 16, 26, 8) };
            if (bannerStyle) p.BackColor = Color.White;
            pages.Controls.Add(p);
            return p;
        }

        protected void ShowPage(Panel page, string pageTitle = null, string pageSubtitle = null)
        {
            bool bannerStyle = (bool)page.Tag;
            header.Visible = !bannerStyle;
            headerLine.Visible = !bannerStyle;
            banner.Visible = bannerStyle;
            foreach (Control c in pages.Controls) c.Visible = c == page;
            if (pageTitle != null) title.Text = pageTitle;
            if (pageSubtitle != null) subtitle.Text = pageSubtitle;
        }

        /// <summary>Lays out controls top to bottom inside a page; wrapped labels take the height they need.</summary>
        protected static FlowLayoutPanel Stack(Panel page)
        {
            var f = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, WrapContents = false, AutoScroll = false };
            page.Controls.Add(f);
            return f;
        }

        protected Label Para(Control parent, string text, int width, int top = 0, Font font = null)
        {
            var l = new Label { AutoSize = true, MaximumSize = new Size(width, 0), Text = text, Margin = new Padding(0, top, 0, 0) };
            if (font != null) l.Font = font;
            parent.Controls.Add(l);
            return l;
        }

        protected int PageWidth(bool bannerStyle) => bannerStyle ? W - BannerW - 44 : W - 52;

        protected Font Bold(float size) => new Font("Segoe UI", size, FontStyle.Bold);
        protected Font Big => new Font("Segoe UI", 13F, FontStyle.Bold);

        class BannerPanel : Panel
        {
            public BannerPanel() { DoubleBuffered = true; ResizeRedraw = true; }

            protected override void OnPaint(PaintEventArgs e)
            {
                var g = e.Graphics;
                g.SmoothingMode = SmoothingMode.AntiAlias;
                var r = ClientRectangle;
                using (var b = new LinearGradientBrush(r, Color.FromArgb(12, 28, 60), Color.FromArgb(24, 86, 190), LinearGradientMode.Vertical))
                    g.FillRectangle(b, r);
                // orange sweep in the lower corner
                using (var path = new GraphicsPath())
                {
                    path.AddPolygon(new[] { new PointF(0, r.Height * 0.78f), new PointF(r.Width, r.Height * 0.60f), new PointF(r.Width, r.Height), new PointF(0, r.Height) });
                    using (var b = new LinearGradientBrush(r, Color.FromArgb(255, 160, 60), Color.FromArgb(225, 95, 15), LinearGradientMode.Horizontal))
                        g.FillPath(b, path);
                }
                float s = r.Width * 0.46f;
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                g.DrawImage(Logo, (r.Width - s) / 2, r.Height * 0.12f, s, s);
                using (var f1 = new Font("Segoe UI", 20F, FontStyle.Bold, GraphicsUnit.Point))
                using (var f2 = new Font("Segoe UI", 9.5F, FontStyle.Regular, GraphicsUnit.Point))
                using (var sf = new StringFormat { Alignment = StringAlignment.Center })
                {
                    float y = r.Height * 0.12f + s + r.Height * 0.04f;
                    g.DrawString("RLMM", f1, Brushes.White, new RectangleF(0, y, r.Width, 50), sf);
                    y += f1.GetHeight(g) + 2;
                    using (var b = new SolidBrush(Color.FromArgb(200, 220, 255)))
                        g.DrawString("UDK for Rocket League\nmap making", f2, b, new RectangleF(0, y, r.Width, 60), sf);
                }
            }
        }
    }
}
