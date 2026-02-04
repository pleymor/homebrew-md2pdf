class Md2pdf < Formula
  desc "Convert Markdown to PDF with Mermaid diagram support"
  homepage "https://github.com/pleymor/md2pdf"
  url "https://github.com/pleymor/md2pdf/archive/refs/tags/v1.0.1.tar.gz"
  sha256 "d10217b06fd93ab4e9f55b7ec3c90cd4694479907c55e057d04775a9e18130e5"
  license "MIT"

  depends_on "docker" => :build

  def install
    libexec.install "md2pdf.sh", "templates", "filters", "Dockerfile"
    (bin/"md2pdf").write_env_script libexec/"md2pdf.sh", {}
  end

  def caveats
    <<~EOS
      Docker must be running to use md2pdf.
      The first run will build the Docker image automatically.

      Usage:
        md2pdf document.md
        md2pdf document.md --logo logo.png
    EOS
  end

  test do
    assert_match "Usage:", shell_output("#{bin}/md2pdf --help", 1)
  end
end
