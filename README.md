# 0) Launch an Ubuntu 24.04 EC2 and SSH in (user: ubuntu)

# 1) Clone this repo

```bash
git clone https://github.com/ijapesigan/ipractise-rstudio-build.git
cd ipractise-rstudio-build
```

# 2) Make scripts executable

```bash
chmod +x run.sh install-r-from-source.sh install-rstudio-server.sh configure-posit-ppm.sh
```

# 3) Run everything (auto sudo)

```bash
./run.sh
```

# 4) Log-in to RStudio server (http://<EC2-Public-DNS>:8787)

```bash
Username: rstudio
Password: rstudio
```

# 5) Change the password in the RStudio terminal

```bash
sudo passwd rstudio
```
