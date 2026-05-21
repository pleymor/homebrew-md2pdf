class Md2pdf < Formula
  desc "Convert Markdown to PDF with Mermaid diagram support"
  homepage "https://github.com/pleymor/md2pdf"
  url "https://github.com/pleymor/md2pdf/archive/refs/tags/v1.3.0.tar.gz"
  version "1.3.0"
  sha256 "a45df0c86280cbaa9587dbb8caf688fefc786a19a7df6f34153c96d8d0caecf7"
  license "MIT"

  def install
    libexec.install "md2pdf.sh", "templates", "filters", "Dockerfile"
    (bin/"md2pdf").write_env_script libexec/"md2pdf.sh", {}
  end

  def caveats
    <<~EOS
      Docker or Podman must be installed and running to use md2pdf.
      The engine is auto-detected (Docker preferred); override it with
      MD2PDF_CONTAINER_ENGINE=podman. The first run builds the image automatically.

      Usage:
        md2pdf document.md
        md2pdf document.md --logo logo.png
    EOS
  end

  test do
    assert_match "Usage:", shell_output("#{bin}/md2pdf --help", 1)
  end
end