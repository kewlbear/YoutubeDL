"""
My first application
"""
import youtube_dl

def main():
    ydl_opts = {'nocheckcertificate': True}
#    with youtube_dl.YoutubeDL(ydl_opts) as ydl:
#        ydl.download(['https://www.youtube.com/watch?v=BaW_jenozKc'])

def progress_hook(progress):
    print('progress', progress)
