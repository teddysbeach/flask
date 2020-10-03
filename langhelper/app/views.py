from app import app, db
from app.models import User, Post
from flask import render_template, request


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

@app.route('/register', methods=['POST', 'GET'])
def register():
    if request.method == 'GET':
        return render_template("register.html")
    else:
        username = request.form['username']
        nickname = request.form['nickname']
        password = request.form['password']
        email = request.form['email']
        user = User(username, nickname, password, email)
        db.session.add(user)
        db.session.commit()
        return render_template("users.html")    
