#!/bin/bash

# Scriptin hata ayıklama modunu etkinleştir
set -e

# Renk kodları
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Ilerleme çubuğu fonksiyonu
progress_bar() {
    local duration=${1}
    local interval=0.1
    local elapsed=0
    local bar_length=50

    while (( $(echo "$elapsed < $duration" | bc -l) )); do
        local progress=$(echo "$elapsed / $duration" | bc -l)
        local filled_length=$(echo "$bar_length * $progress" | bc | awk '{printf "%d", $0}')
        local empty_length=$((bar_length - filled_length))

        printf "\r[${BLUE}$(printf '%*s' "$filled_length" | tr ' ' '#')$(printf '%*s' "$empty_length" | tr ' ' ' ')${NC}]"
        sleep $interval
        elapsed=$(echo "$elapsed + $interval" | bc)
    done
    echo -e "\n"
}

# Gerekli izinlerin kontrolü
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Bu scripti çalıştırmak için root (sudo) yetkilerine ihtiyacınız var.${NC}"
  exit 1
fi

# Docker'ı kaldır
echo -e "${YELLOW}Eski Docker bileşenlerini kaldırıyor...${NC}"
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
    sudo apt-get remove -y $pkg
done
progress_bar 2

# Paket listelerini güncelle
echo -e "${YELLOW}Paket listelerini güncelliyor...${NC}"
sudo apt-get update
progress_bar 2

# Gerekli paketleri yükle
echo -e "${YELLOW}Gerekli paketleri yüklüyor...${NC}"
sudo apt-get install -y ca-certificates curl
progress_bar 2

# Docker GPG anahtarını ekle
echo -e "${YELLOW}Docker GPG anahtarını ekliyor...${NC}"
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
progress_bar 2

# Docker deposunu ekle
echo -e "${YELLOW}Docker deposunu ekliyor...${NC}"
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
progress_bar 2

# Paket listelerini tekrar güncelle
echo -e "${YELLOW}Paket listelerini tekrar güncelliyor...${NC}"
sudo apt-get update
progress_bar 2

# Docker'ı kur
echo -e "${YELLOW}Docker'ı kuruyor...${NC}"
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
progress_bar 2

# Swap'ı kapat
echo -e "${YELLOW}Swap'ı kapatıyor...${NC}"
sudo swapoff -a
progress_bar 2

# /etc/fstab dosyasındaki swap satırını yorum satırı haline getir
echo -e "${YELLOW}Swap ayarlarını /etc/fstab dosyasına yorum satırı ekliyor...${NC}"
sudo awk '{if($0 ~ /\/swapfile/) print "#" $0; else print $0}' /etc/fstab > /etc/fstab.tmp && sudo mv /etc/fstab.tmp /etc/fstab
progress_bar 2

# Gerekli modülleri yüklemek için k8s.conf dosyasını oluştur
echo -e "${YELLOW}Gerekli modülleri içeren k8s.conf dosyasını oluşturuyor...${NC}"
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
progress_bar 2

# Modülleri yükle
echo -e "${YELLOW}Modülleri yüklüyor...${NC}"
sudo modprobe overlay
sudo modprobe br_netfilter
progress_bar 2

# Gerekli sysctl parametrelerini ayarlamak için k8s.conf dosyasını oluştur
echo -e "${YELLOW}Sysctl parametrelerini ayarlamak için k8s.conf dosyasını oluşturuyor...${NC}"
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
progress_bar 2

# Sysctl parametrelerini uygulama
echo -e "${YELLOW}Sysctl parametrelerini uyguluyor...${NC}"
sudo sysctl --system
progress_bar 2

# Containerd dizinini oluştur
echo -e "${YELLOW}Containerd dizinini oluşturuyor...${NC}"
sudo mkdir -p /etc/containerd 
progress_bar 2

# Containerd varsayılan ayarlarını config.toml dosyasına yaz
echo -e "${YELLOW}Containerd varsayılan ayarlarını config.toml dosyasına yazıyor...${NC}"
sudo sh -c "containerd config default > /etc/containerd/config.toml"
progress_bar 2

# SystemdCgroup ayarını true olarak değiştir
echo -e "${YELLOW}SystemdCgroup ayarını true olarak değiştiriyor...${NC}"
sudo sed -i 's/ SystemdCgroup = false/ SystemdCgroup = true/' /etc/containerd/config.toml
progress_bar 2

# Containerd servisini yeniden başlat
echo -e "${YELLOW}Containerd servisini yeniden başlatıyor...${NC}"
sudo systemctl restart containerd.service
progress_bar 2

# Kubectl'yi indir
echo -e "${YELLOW}Kubectl'yi indiriyor...${NC}"
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
progress_bar 2

# İndirdiğiniz kubectl dosyasını çalıştırılabilir hale getirin
echo -e "${YELLOW}İndirilen kubectl dosyasını çalıştırılabilir hale getiriyor...${NC}"
chmod +x ./kubectl
progress_bar 2

# Kubectl'yi /usr/local/bin dizinine taşıyın
echo -e "${YELLOW}Kubectl'yi /usr/local/bin dizinine taşıyor...${NC}"
sudo mv ./kubectl /usr/local/bin/kubectl
progress_bar 2

# Paket listelerini güncelle
echo -e "${YELLOW}Paket listelerini güncelliyor...${NC}"
sudo apt-get update
progress_bar 2

# Gerekli paketleri yükle
echo -e "${YELLOW}Gerekli paketleri yüklüyor...${NC}"
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg
progress_bar 2

# Kubernetes APT anahtarını ekle
echo -e "${YELLOW}Kubernetes APT anahtarını ekliyor...${NC}"
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
progress_bar 2

# Kubernetes APT kaynak listesini ekle
echo -e "${YELLOW}Kubernetes APT kaynak listesini ekliyor...${NC}"
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
progress_bar 2

# Paket listelerini tekrar güncelle
echo -e "${YELLOW}Paket listelerini tekrar güncelliyor...${NC}"
sudo apt-get update
progress_bar 2

# Kubernetes bileşenlerini yükle
echo -e "${YELLOW}Kubernetes bileşenlerini yüklüyor...${NC}"
sudo apt-get install -y kubelet kubeadm kubectl
progress_bar 2

# Kubernetes bileşenlerini durdurma
echo -e "${YELLOW}Kubernetes bileşenlerini durduruyor...${NC}"
sudo apt-mark hold kubelet kubeadm kubectl
progress_bar 2

# Kubelet servisini etkinleştir ve başlat
echo -e "${YELLOW}Kubelet servisini etkinleştiriyor ve başlatıyor...${NC}"
sudo systemctl enable --now kubelet
progress_bar 2

# Otomatik tamamlama ayarlarını ekle
echo -e "${YELLOW}Otomatik tamamlama ayarlarını ekliyor...${NC}"
echo "source <(kubectl completion bash)" >> ~/.bashrc
echo "source <(kubeadm completion bash)" >> ~/.bashrc

# Değişikliklerin etkili olması için terminali yeniden başlatma
echo -e "${YELLOW}Değişikliklerin etkili olması için terminali yeniden başlatın veya aşağıdaki komutu çalıştırın:${NC}"
echo -e "${GREEN}source ~/.bashrc${NC}"
echo -e "${YELLOW}Kubernetes HA yapı için aşağıdaki komutu düzenleyerek çalıştırın:${NC}"
echo -e "${GREEN}kubeadm init --pod-network-cidr=10.0.0.0/16 --control-plane-endpoint="MasterIP" --upload-certs${NC}"
echo -e "${GREEN}Kubernetes kurulumu için gerekli ayarlar tamamlandı!${NC}"
