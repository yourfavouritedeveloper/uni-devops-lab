from flask import Flask
import os, redis

app = Flask(__name__)
r = redis.Redis(host=os.getenv('REDIS_HOST', 'localhost'), port=6379)

@app.route('/')
def home():
    return 'University Student Portal is running'

@app.route('/health')
def health():
    return {'status': 'healthy'}

@app.route('/visits')
def visits():
    return {'visits': r.incr('visits')}

app.run(host='0.0.0.0', port=5000)
