# create_v2_secrets.ps1
# PowerShell-safe AWS Secrets Manager setup for V2.

$Region = "eu-west-2"

Write-Host "Creating V2 Secrets in AWS Secrets Manager..." -ForegroundColor Cyan

##############################################
# 1) DB PASSWORD SECRET
##############################################
aws secretsmanager create-secret `
  --name "/custom-snipeit-v2/db_password" `
  --description "Snipe-IT V2 MySQL password" `
  --secret-string '{"value":"H0st_290_8X8"}' `
  --region $Region

##############################################
# 2) APP_KEY SECRET
##############################################
aws secretsmanager create-secret `
  --name "/custom-snipeit-v2/app_key" `
  --description "APP_KEY for Snipe-IT V2" `
  --secret-string '{"value":"base64:R4J5JUcP+eBicCq/RdB7JByW9bXRhOnuZfKQ8DU68nU="}' `
  --region $Region

##############################################
# 3) API TOKEN SECRET (placeholder)
##############################################
aws secretsmanager create-secret `
  --name "/custom-snipeit-v2/snipeit_api_token" `
  --description "JWT API token for Snipe-IT V2" `
  --secret-string '{"value":"PLACEHOLDER"}' `
  --region $Region

##############################################
# 4) FLASK SECRET KEY
##############################################
aws secretsmanager create-secret `
  --name "/custom-snipeit-v2/flask_secret_key" `
  --description "Flask SECRET_KEY for V2" `
  --secret-string '{"value":"f508548be09f05eee885065f57a967bbb85da8df16b138681c9e4037620537b5"}' `
  --region $Region

Write-Host "Secrets created successfully!" -ForegroundColor Green
