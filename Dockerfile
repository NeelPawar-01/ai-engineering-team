FROM python:3.12-slim

WORKDIR /app

COPY . .

RUN pip install --upgrade pip
RUN pip install crewai
RUN pip install .

CMD ["engineering_team"]