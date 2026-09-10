pkgname=Arch-in-ram
pkgver=7e99e61
pkgrel=1
pkgdesc="hooks and other files to make an arch linux system boot to ram"
arch=('any')
url="https://github.com/alivehamster/Arch-in-ram"
makedepends=('git')
install=${pkgname}.install
source=("$pkgname::git+file://$(pwd)/.git")
sha256sums=('SKIP')

package() {
  cd "$srcdir/$pkgname/scripts"

  install -Dm755 air-manage.sh "${pkgdir}/usr/bin/air-manage"
  install -Dm644 install/boottoram "${pkgdir}/etc/initcpio/install/boottoram"
  install -Dm644 hooks/boottoram "${pkgdir}/etc/initcpio/hooks/boottoram"

  install -Dm644 hooks/boottoram "${pkgdir}/usr/share/arch-in-ram/boottoram"
  install -Dm644 systemd-boot/entries/arch.conf "${pkgdir}/usr/share/arch-in-ram/arch.conf"
}
