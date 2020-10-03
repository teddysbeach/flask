from app import app, db
from app.models import User, Post
from flask import render_template, redirect, url_for, request, session, flash


@app.route('/')
def hello_world():
    if('username' in session):
        return render_template("index.html", user=session['username'])
    else:
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

@app.route('/login', methods=['POST', 'GET'])
def login():
    if request.method == 'GET':
        return render_template("login.html")
    else:
        username = request.form['username']
        password = request.form['password']
        result = User.query.filter_by(username=username).first()
        if(result):
            if(result.tryLogin(password)):
                session['username'] = username
                flash('You were successfully logged in!')
                return redirect(url_for("index"))
            else:
                flash('Something is wrong. It could be your account or password')
                return redirect(url_for('login'))

        else:
            flash('I couldn\'t find your account dude.')
            return redirect(url_for('login'))
