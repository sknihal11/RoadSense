import sys

# 1. Mock 'crypt' module for Python 3.12+ compatibility in Vercel's serverless environment
try:
    import crypt
except ImportError:
    import types
    crypt_module = types.ModuleType("crypt")
    def dummy_crypt(word, salt):
        return salt
    crypt_module.crypt = dummy_crypt
    sys.modules["crypt"] = crypt_module

# 2. Monkey-patch bcrypt to satisfy passlib's legacy checks in modern environments
import bcrypt
if not hasattr(bcrypt, "__about__"):
    class About:
        __version__ = bcrypt.__version__
    bcrypt.__about__ = About()

# 3. Import the main FastAPI application
from app.main import app
