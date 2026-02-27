class Md2pdf < Formula
  desc "Convert Markdown to PDF with Mermaid diagram support"
  homepage "https://github.com/pleymor/md2pdf"
  url "https://github.com/pleymor/md2pdf/archive/refs/tags/v1.1.0.tar.gz"
  version "1.1.0"
  sha256 "58a1fe2e27ed2c2bac756db2eff162cd4b80a9d05dbeb42bf441f7d08993da8f"
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