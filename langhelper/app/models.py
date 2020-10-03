from app import app, db
from werkzeug.security import generate_password_hash, check_password_hash
import datetime

class User(db.Model):
    __table_name__ = 'user'
    __table_args__ = {'useexisting': True}
    
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(100), unique=True, nullable=False)
    email = db.Column(db.String(120), unique=True, nullable=False)
    password = db.Column(db.String(255), nullable=False)
    nickname = db.Column(db.String(40), unique=True, nullable=False)
    profileImg = db.Column(db.String(100), default="default.png")

    posts = db.relationship('Post', backref='author', lazy=True)
    
    def __init__(self, username, nickname, password, email):
        self.username = username
        self.email = email
        self.nickname = nickname
        self.password = self.setPassword(password)
    
    def setPassword(self, password):
        return generate_password_hash(password)
    
    def tryLogin(self, password):
        return check_password_hash(self.password, password)
        
    def __repr__(self):
        return f"<User('{self.id}', '{self.username}', '{self.email}')>"

class Post(db.Model):
    __table_name__ = 'post'
    
    id = db.Column(db.Integer, primary_key=True)
    title = db.Column(db.String(100), nullable=False)
    content = db.Column(db.Text, nullable=False)
    datePosted = db.Column(db.DateTime, default=datetime.datetime.now())
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'))
    
    def __repr__(self):
        return f"<Post('{self.id}', '{self.title}')>"