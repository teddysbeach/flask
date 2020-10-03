from app import app
from app.models import User, Post
from flask import render_template

@app.route('/')
def hello_world():
    return render_template("index.html")

@app.route('/diary')
def showlists():
    return render_template("diary.html")

@app.route('/users')
def showUsers():
    users = User.query.all()
    return render_template("users.html", users=users)