FROM nginx:alpine

# 复制构建产物
COPY build/web /usr/share/nginx/html

# 复制 nginx 配置
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80
