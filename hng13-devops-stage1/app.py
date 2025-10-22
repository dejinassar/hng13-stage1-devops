from flask import Flask, render_template
from datetime import datetime

app = Flask(__name__)

# ---------- Deployment Info ----------
DEVOPS_STAGE = "Stage 1"
DEV_NAME = "Ibrahim Nassar"
DEPLOY_DATE = datetime.now().strftime("%d/%m/%Y")

@app.route('/')
def home():
    return render_template(
        "index.html",
        stage=DEVOPS_STAGE,
        dev_name=DEV_NAME,
        deploy_date=DEPLOY_DATE
    )

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
