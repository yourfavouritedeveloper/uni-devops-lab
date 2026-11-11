# uni-devops-lab

Universitet tələbə portalının (Flask + Redis) Git ilə idarə olunması, Docker ilə paketlənməsi və Ansible ilə app server-ə avtomatik qurulması.

## Struktur

```
app/                  Flask tətbiqi (app.py, requirements.txt)
Dockerfile            python:3.12-slim əsaslı portal image-i
compose.yml           portal + redis, redis-data named volume
ansible/
  ansible.cfg
  inventory.ini       app server (şifrəsiz SSH, key ilə)
  group_vars/app_servers.yml   port, image adı, qovluq yolu və s. dəyişənlər
  playbook.yml        Docker quraşdırma, faylların köçürülməsi, compose up, /health yoxlaması
  requirements.yml    community.docker collection
lab/                  lokal test app server-i (Ubuntu 24.04 + systemd + SSH, Docker-siz)
docs/                 playbook-un 1-ci və 2-ci icrasının çıxışı
```

## Git iş axını

Hər mərhələ ayrıca branch-də görülüb və Pull Request (Merge Request) ilə `main`-ə birləşdirilib:

| Branch | Məzmun |
|---|---|
| `feature/app-setup` | tətbiq kodu, requirements, `.gitignore` |
| `feature/docker` | Dockerfile, compose.yml |
| `feature/ansible` | inventory, dəyişənlər, playbook, lab server, README |

`.gitignore` `.env`, `*.log`, private key fayllarını (`*.pem`, `*.key`, `id_*`) repository-dən kənarda saxlayır. Repository-də heç bir parol, token və ya private key yoxdur.

## Docker (lokal yoxlama)

```bash
docker build -t student-portal:1.0 .
docker compose up -d
curl localhost:8080/health    # {"status":"healthy"}
curl localhost:8080/visits    # {"visits":1}
docker compose restart
curl localhost:8080/visits    # {"visits":2} — sıfırlanmır
```

- Dockerfile-da əvvəl `requirements.txt` kopyalanıb `pip install` edilir, sonra kod — kod dəyişəndə asılılıq layer-i cache-dən gəlir.
- Portal Redis-ə servis adı ilə qoşulur: `REDIS_HOST=redis`.
- Redis `--appendonly yes` ilə işləyir, data `redis-data` named volume-da saxlanılır.

## Ansible

```bash
# 1. (yalnız lokal test üçün) app server-i qaldır və SSH key-i icazələndir
./lab/start-app-server.sh

# 2. collection-u quraşdır və playbook-u işə sal
cd ansible
ansible-galaxy collection install -r requirements.yml
ansible app_servers -m ping
ansible-playbook playbook.yml
```

Playbook:
1. Docker-in rəsmi apt repository-sini əlavə edir, Docker Engine + Compose plugin quraşdırır, servisi `started` + `enabled` edir.
2. `Dockerfile`, `compose.yml`, `app/` fayllarını `{{ app_dir }}`-a köçürür, image adı və portu `.env` faylına yazır.
3. `community.docker.docker_compose_v2` ilə servisləri qaldırır. Image yalnız fayllar dəyişəndə yenidən build edilir.
4. `/health` endpoint-ini yoxlayır və nəticəni ekrana çıxarır.

Port, image adı və qovluq yolu `group_vars/app_servers.yml`-dadır, playbook-da hard-code edilməyib.

**Nəticə:** birinci icra `changed=9`, ikinci icra `changed=0` (idempotent) — bax `docs/playbook-run1.txt`, `docs/playbook-run2.txt`. Portal `http://<server-ip>:8080`-dan açılır.

## Qarşılaşdığım problem

App server kimi lokal Ubuntu konteyneri (Docker-in-Docker) istifadə etdim. Playbook-un ilk icrasında image build mərhələsi bu xəta ilə dayandı:

```
failed to solve: mount source: "overlay" ... err: invalid argument
```

**Səbəb:** daxili Docker/containerd öz layer-lərini overlayfs ilə saxlayır, lakin `/var/lib/containerd` qovluğu özü də konteynerin overlay fayl sistemində idi — overlay üzərində overlay mount etmək olmur. `/var/lib/docker` üçün volume vermişdim, amma Docker 29 image-ləri containerd snapshotter-də saxladığı üçün `/var/lib/containerd` da lazım idi.

**Həll:** `lab/start-app-server.sh`-də `/var/lib/containerd` üçün də ayrıca named volume əlavə etdim. Bundan sonra playbook təmiz serverdə uğurla işlədi.
