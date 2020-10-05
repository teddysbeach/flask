from app import app, db
from app.models import User, Post
from flask import render_template, redirect, url_for, request, session, flash, g
import datetime
from app.decorator import login_required
from sqlalchemy import desc

@app.route('/')
@app.route('/index')
def index():
    return render_template("index.html")
    
@app.before_request
def loadSession():
    username = session.get('username')
    if username is None:
        g.user = None
    else:
        g.user = User.query.filter_by(username=username).first()

@app.route('/notebook')
@login_required
def notebook():
    return render_template("notebook.html")

@app.route('/diary')
@login_required
def diary():
    posts = Post.query.order_by(desc('datePosted')).all()
    return render_template("diary.html", posts=posts)

@app.route('/diary/new', methods=['POST'])
@login_required
def diaryNew():
    if(request.method == 'POST'):
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
        return redirect(url_for('index'))


@app.route('/users')
@login_required
def showUsers():
    users = User.query.all()
    return render_template("users.html", users=users)

@app.route('/register', methods=['POST', 'GET'])
def register():
    if request.method == 'GET':
        if('username' in session):
            return redirect(url_for('index'))
        else:
            return render_template("register.html")
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
@login_required
def me():
    user = User.query.filter_by(username=session['username']).first()
    return render_template('me.html', user=user)

@app.errorhandler(404)
def page_not_found(e):
    return render_template('errors/404.html')
