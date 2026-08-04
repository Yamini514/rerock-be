FROM ruby:3.4.1


RUN apt-get update && apt-get -y install libpq-dev gcc

WORKDIR /app

COPY Gemfile* .

RUN bundle install

COPY . .

RUN chmod +x docker-entrypoint.sh

ENTRYPOINT ["./docker-entrypoint.sh"]
CMD ["puma", "-p", "8080", "-b", "tcp://0.0.0.0"]