from app import app, db
from app.models import User, Post
from flask import render_template, redirect, url_for, request, session, flash
import datetime
from sqlalchemy import desc
@app.route('/')
@app.route('/index')
def index():
    return render_template("index.html")

@app.route('/notebook')
def notebook():
    return render_template("notebook.html")

@app.route('/diary')
def diary():
    posts = Post.query.order_by(desc('datePosted')).all()
    return render_template("diary.html", posts=posts)

@app.route('/diary/new', methods=['POST'])
def diaryNew():
    if(request.method == 'POST'):
        if('username' in session):
            user = User.query.filter_by(username=session['username']).first()
            if(request.form['date']):
                date = datetime.datetime.strptime(request.form['date'], '%Y-%m-%d')
            else:
                date = datetime.datetime.today()
            content = request.form['content']
            post = Post(title=date.__str__(), content=content, datePosted=date, user_id=user.id)
            db.session.add(post)
            db.session.commit()
            return redirect(url_for('diary'))
        else:
            return redirect(url_for("login"))
    else:
        return redirect(url_for('index'))
@app.route('/users')
def showUsers():
    users = User.query.all()
    return render_template("users.html", users=users)

@app.route('/register', methods=['POST', 'GET'])
def register():
    if request.method == 'GET':
        if('username' in session):
            return redirect(url_for('index'))
        else:
            return redirect(url_for("register"))
    else:
        username = request.form['username']
        nickname = request.form['nickname']
        password = request.form['password']
        email = request.form['email']
        user = User(username, nickname, password, email)
        db.session.add(user)
        db.session.commit()
        return redirect(url_for("showUsers"))    

@app.route('/login', methods=['POST', 'GET'])
def login():
    if request.method == 'GET':
        if('username' in session):
            return redirect(url_for('me'))
        else:
            return render_template(("login.html"))
    else:
        username = request.form['username']
        password = request.form['password']
        result = User.query.filter_by(username=username).first()
        if(result):
            if(result.tryLogin(password)):
                session['username'] = username
                return redirect(url_for('index'))
            else:
                flash('Something is wrong. It could be your account or password')
                return render_template('login.html')

        else:
            flash('I couldn\'t find your account dude.')
            return render_template('login.html')

@app.route('/logout')
def logout():
    if ('username' in session):
        session.pop('username')
    return redirect(url_for('login'))

@app.route('/me')
def me():
    if ('username' in session):
        user = User.query.filter_by(username=session['username']).first()
        return render_template('me.html', user=user)
    else:
        flash('To enter this page, you need to login first!')
        return redirect(url_for('login'))
