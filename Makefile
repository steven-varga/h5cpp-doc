all:
	mkdocs build

upload: all
	rsync -az  site/ osaka:sandbox/

view:
	xdg-open  http://127.0.0.1:8000
	mkdocs serve

clean:
	$(RM) -rf site



