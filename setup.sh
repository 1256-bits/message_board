#!/usr/bin/env bash

# Message Board Setup Script with Topic Authors and Pagination
# Creates a password-protected Flask message board with SQLite backend

set -e

# Check if running as root
if [ "$(id -u)" -eq 0 ]; then
    echo "This script should not be run as root. Please run as a normal user."
    exit 1
fi

# Create project directory
PROJECT_DIR="message_board"
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

# Create directory structure
mkdir -p instance static templates

# Create requirements.txt
cat > requirements.txt << 'EOL'
Flask==3.0.2
python-dotenv==1.0.1
Flask-SQLAlchemy==3.1.1
EOL

# Create .gitignore
cat > .gitignore << 'EOL'
instance/
.env
__pycache__/
*.pyc
*.pyo
*.pyd
.Python
env/
venv/
.venv/
EOL

# Create app.py with topic authors
cat > app.py << 'EOL'
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
    author = db.Column(db.String(50), nullable=True)
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

# Authentication decorator
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
@app.route('/topics')
@app.route('/topics/<int:page>')
@login_required
def list_topics(page=1):
    topics = Topic.query.order_by(Topic.id.desc()).paginate(page=page, per_page=20)
    return render_template('topics.html', topics=topics)

@app.route('/topic/<int:topic_id>')
@app.route('/topic/<int:topic_id>/<int:page>')
@login_required
def view_topic(topic_id, page=1):
    topic = Topic.query.get_or_404(topic_id)
    messages = Message.query.filter_by(topic_id=topic_id).order_by(Message.id.desc()).paginate(page=page, per_page=10)
    
    # Get username from cookie or form
    username = request.cookies.get('username') or ''
    
    return render_template('topic.html', topic=topic, messages=messages, username=username)

@app.route('/topic/new', methods=['GET', 'POST'])
@login_required
def new_topic():
    username = request.cookies.get('username') or ''
    
    if request.method == 'POST':
        title = request.form.get('title')
        author = request.form.get('username')
        
        if not title:
            flash('Topic title cannot be empty', 'error')
            return redirect(url_for('new_topic'))
        
        topic = Topic(title=title, author=author[:50] if author else None)
        db.session.add(topic)
        db.session.commit()
        
        response = redirect(url_for('view_topic', topic_id=topic.id))
        if author:
            response.set_cookie('username', author, max_age=30*24*60*60)  # 30 days
        
        return response
    
    return render_template('new_topic.html', username=username)

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
EOL

# Create wsgi.py
cat > wsgi.py << 'EOL'
from app import app

if __name__ == "__main__":
    app.run()
EOL

# Create templates
# base.html remains the same
cat > templates/base.html << 'EOL'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Message Board</title>
    <style>
        body { font-family: Arial, sans-serif; max-width: 800px; margin: 0 auto; padding: 20px; }
        .header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px; }
        .messages { margin: 20px 0; }
        .message { border-bottom: 1px solid #eee; padding: 10px 0; }
        .message-meta { font-size: 0.8em; color: #666; margin-bottom: 5px; }
        .topic-meta { font-size: 0.9em; color: #555; margin: 5px 0; }
        .pagination { margin: 20px 0; }
        .pagination a { margin: 0 5px; }
        form { margin: 20px 0; }
        textarea { width: 100%; height: 100px; }
        input[type="text"] { width: 200px; }
        .error { color: red; }
        .success { color: green; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Message Board</h1>
        <div>
            <a href="{{ url_for('list_topics') }}">Topics</a> |
            <a href="{{ url_for('new_topic') }}">New Topic</a> |
            <a href="{{ url_for('logout') }}">Logout</a>
        </div>
    </div>
    
    {% with messages = get_flashed_messages(with_categories=true) %}
        {% if messages %}
            {% for category, message in messages %}
                <div class="{{ category }}">{{ message }}</div>
            {% endfor %}
        {% endif %}
    {% endwith %}
    
    {% block content %}{% endblock %}
</body>
</html>
EOL

# login.html remains the same
cat > templates/login.html << 'EOL'
{% extends "base.html" %}

{% block content %}
    <h2>Login</h2>
    <form method="POST">
        <div>
            <label for="password">Password:</label>
            <input type="password" id="password" name="password" required>
        </div>
        <button type="submit">Login</button>
    </form>
{% endblock %}
EOL

# Updated topics.html with author display
cat > templates/topics.html << 'EOL'
{% extends "base.html" %}

{% block content %}
    <h2>Topics</h2>
    <a href="{{ url_for('new_topic') }}">Create New Topic</a>
    
    <ul>
        {% for topic in topics.items %}
            <li>
                <a href="{{ url_for('view_topic', topic_id=topic.id) }}">{{ topic.title }}</a>
                <div class="topic-meta">
                    {% if topic.author %}
                        Created by <strong>{{ topic.author }}</strong> - 
                    {% else %}
                        Created by <strong>Anonymous</strong> - 
                    {% endif %}
                    {{ topic.messages|length }} messages
                </div>
            </li>
        {% endfor %}
    </ul>
    
    <div class="pagination">
        {% if topics.has_prev %}
            <a href="{{ url_for('list_topics', page=topics.prev_num) }}">Previous</a>
        {% endif %}
        
        {% for page_num in topics.iter_pages() %}
            {% if page_num %}
                {% if topics.page == page_num %}
                    <strong>{{ page_num }}</strong>
                {% else %}
                    <a href="{{ url_for('list_topics', page=page_num) }}">{{ page_num }}</a>
                {% endif %}
            {% else %}
                ...
            {% endif %}
        {% endfor %}
        
        {% if topics.has_next %}
            <a href="{{ url_for('list_topics', page=topics.next_num) }}">Next</a>
        {% endif %}
    </div>
{% endblock %}
EOL

# Updated topic.html with author display
cat > templates/topic.html << 'EOL'
{% extends "base.html" %}

{% block content %}
    <h2>{{ topic.title }}</h2>
    <div class="topic-meta">
        {% if topic.author %}
            Topic created by <strong>{{ topic.author }}</strong>
        {% else %}
            Topic created by <strong>Anonymous</strong>
        {% endif %}
    </div>
    
    <div class="messages">
        {% for message in messages.items %}
            <div class="message">
                <div class="message-meta">
                    {% if message.username %}
                        <strong>{{ message.username }}</strong> - 
                    {% else %}
                        <strong>Anonymous</strong> - 
                    {% endif %}
                    {{ message.created_at.strftime('%Y-%m-%d %H:%M') }}
                </div>
                <div class="message-content">{{ message.content }}</div>
            </div>
        {% endfor %}
    </div>
    
    <div class="pagination">
        {% if messages.has_prev %}
            <a href="{{ url_for('view_topic', topic_id=topic.id, page=messages.prev_num) }}">Previous</a>
        {% endif %}
        
        {% for page_num in messages.iter_pages() %}
            {% if page_num %}
                {% if messages.page == page_num %}
                    <strong>{{ page_num }}</strong>
                {% else %}
                    <a href="{{ url_for('view_topic', topic_id=topic.id, page=page_num) }}">{{ page_num }}</a>
                {% endif %}
            {% else %}
                ...
            {% endif %}
        {% endfor %}
        
        {% if messages.has_next %}
            <a href="{{ url_for('view_topic', topic_id=topic.id, page=messages.next_num) }}">Next</a>
        {% endif %}
    </div>
    
    <form method="POST" action="{{ url_for('add_message', topic_id=topic.id) }}">
        <div>
            <label for="username">Name (optional):</label>
            <input type="text" id="username" name="username" value="{{ username }}">
        </div>
        <div>
            <label for="content">Message (max 300 chars):</label>
            <textarea id="content" name="content" maxlength="300" required></textarea>
        </div>
        <button type="submit">Post Message</button>
    </form>
{% endblock %}
EOL

# Updated new_topic.html with author field
cat > templates/new_topic.html << 'EOL'
{% extends "base.html" %}

{% block content %}
    <h2>New Topic</h2>
    <form method="POST">
        <div>
            <label for="title">Title:</label>
            <input type="text" id="title" name="title" required>
        </div>
        <div>
            <label for="username">Your Name (optional):</label>
            <input type="text" id="username" name="username" value="{{ username }}">
        </div>
        <button type="submit">Create Topic</button>
    </form>
{% endblock %}
EOL

# Create .env with random password and secret key
cat > .env << EOL
BOARD_PASSWORD="$PASS"
SECRET_KEY="$KEY"
EOL

# Create virtual environment and install requirements
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

# Initialize database
export FLASK_APP=app.py
flask shell << 'EOL'
from app import db
db.create_all()
exit()
EOL

echo "Setup complete!"
echo "The message board has been created in the '$PROJECT_DIR' directory."
echo "A random password has been generated for the board in the .env file."
echo ""
echo "To run the development server:"
echo "  cd $PROJECT_DIR"
echo "  source venv/bin/activate"
echo "  flask run"
echo ""
echo "Or for production with gunicorn:"
echo "  pip install gunicorn"
echo "  gunicorn -w 4 wsgi:app"
echo ""
echo "The admin password is: $(grep BOARD_PASSWORD .env | cut -d '=' -f2)"
