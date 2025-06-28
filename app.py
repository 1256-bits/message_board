import os
from flask import Flask, render_template, request, redirect, url_for, session, flash
from flask_sqlalchemy import SQLAlchemy
from werkzeug.security import check_password_hash
from dotenv import load_dotenv
from functools import wraps

load_dotenv()

app = Flask(__name__)
app.config['SECRET_KEY'] = os.getenv('SECRET_KEY')
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///board.db'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
app.config['PERMANENT_SESSION_LIFETIME'] = 86400  # 1 day in seconds

db = SQLAlchemy(app)

# Models
class Topic(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    title = db.Column(db.String(100), nullable=False)
    messages = db.relationship('Message', backref='topic', lazy=True, cascade='all, delete-orphan')

class Message(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    content = db.Column(db.String(300), nullable=False)
    username = db.Column(db.String(50), nullable=True)
    topic_id = db.Column(db.Integer, db.ForeignKey('topic.id'), nullable=False)
    created_at = db.Column(db.DateTime, server_default=db.func.now())

# Create tables
with app.app_context():
    db.create_all()

# Fixed authentication decorator
def login_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if 'authenticated' not in session:
            return redirect(url_for('login', next=request.url))
        return f(*args, **kwargs)
    return decorated_function

# Routes
@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        password = request.form.get('password')
        if password == os.getenv('BOARD_PASSWORD'):
            session['authenticated'] = True
            session.permanent = True
            next_page = request.args.get('next')
            return redirect(next_page) if next_page else redirect(url_for('list_topics'))
        flash('Invalid password', 'error')
    return render_template('login.html')

@app.route('/logout')
def logout():
    session.clear()
    return redirect(url_for('login'))

@app.route('/')
@login_required
def list_topics():
    topics = Topic.query.order_by(Topic.id.desc()).all()
    return render_template('topics.html', topics=topics)

@app.route('/topic/<int:topic_id>')
@login_required
def view_topic(topic_id):
    page = request.args.get('page', 1, type=int)
    topic = Topic.query.get_or_404(topic_id)
    messages = Message.query.filter_by(topic_id=topic_id).order_by(Message.id.desc()).paginate(page=page, per_page=10)
    
    # Get username from cookie or form
    username = request.cookies.get('username') or ''
    
    return render_template('topic.html', topic=topic, messages=messages, username=username)

@app.route('/topic/new', methods=['GET', 'POST'])
@login_required
def new_topic():
    if request.method == 'POST':
        title = request.form.get('title')
        if title:
            topic = Topic(title=title)
            db.session.add(topic)
            db.session.commit()
            return redirect(url_for('view_topic', topic_id=topic.id))
        flash('Topic title cannot be empty', 'error')
    return render_template('new_topic.html')

@app.route('/topic/<int:topic_id>/message', methods=['POST'])
@login_required
def add_message(topic_id):
    content = request.form.get('content')
    username = request.form.get('username')
    
    if not content:
        flash('Message cannot be empty', 'error')
        return redirect(url_for('view_topic', topic_id=topic_id))
    
    message = Message(
        content=content[:300],  # Enforce max length
        username=username[:50] if username else None,  # Enforce max length and optional
        topic_id=topic_id
    )
    
    db.session.add(message)
    db.session.commit()
    
    response = redirect(url_for('view_topic', topic_id=topic_id))
    if username:
        response.set_cookie('username', username, max_age=30*24*60*60)  # 30 days
    
    return response

if __name__ == '__main__':
    app.run(debug=True)
