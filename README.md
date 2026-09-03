公開鍵と秘密鍵を生成し、AWS IVSに登録する (プライベートチャネルで利用する)
```bash
# Private Keyを生成
openssl ecparam -name secp384r1 -genkey -noout -out priv.pem

# Private KeyからPublic Keyを生成
openssl ec -in priv.pem -pubout -out public.pem
```