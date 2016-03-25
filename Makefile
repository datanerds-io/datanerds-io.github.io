build:
	rm -rf 404.html css img tags index.html index.xml js page post robots.txt sitemap.xml
	hugo -t angels-ladder -s _hugo/ -d ../
run:
	hugo server -t angels-ladder -D -w -s _hugo/
