from app import views
from flask import redirect, url_for, g
from functools import wraps


def login_required(f):
    @wraps(f)
    def wrapped_view(**kwargs):
        if g.user is None:
            return redirect(url_for('login'))
        return f(**kwargs)
    return wrapped_view