pkgname=pacgem
pkgver=0.1.0
pkgrel=1
pkgdesc="Pacman wrapper that offers Gemini CLI troubleshooting on pacman failures"
arch=('any')
license=('MIT')
depends=('bash' 'pacman')
optdepends=('gemini-cli: send pacman errors to Gemini CLI')
options=('!debug')
source=('pacgem' 'LICENSE')
sha256sums=('SKIP' 'SKIP')

package() {
  install -Dm755 pacgem "$pkgdir/usr/bin/pacgem"
  install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}
