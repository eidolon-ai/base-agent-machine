ARG EIDOLON_VERSION=0.1.120
FROM python:3.11-slim as builder
RUN pip install poetry
RUN poetry config virtualenvs.create false --local
COPY pyproject.toml pyproject.toml
COPY poetry.lock poetry.lock
RUN poetry remove eidolon-ai-sdk
COPY components/ components/
COPY README.md README.md
RUN mkdir dist
RUN touch dist/requirements.txt
RUN poetry export --without-hashes --format=requirements.txt > dist/requirements.txt
RUN poetry build

FROM docker.io/eidolonai/sdk_base:$EIDOLON_VERSION as agent-machine-base

# First copy builder requirements so dependency cache layer is cached
COPY --from=builder dist/requirements.txt /tmp/agent-machine/requirements.txt
RUN pip install -r /tmp/agent-machine/requirements.txt --no-cache --no-deps

# Then install poetry project wheel since it will change more frequently
COPY --from=builder dist/*.whl /tmp/agent-machine/
RUN pip install /tmp/agent-machine/*.whl  --no-cache --no-deps


FROM agent-machine-base as agent-machine
# Finally copy resources over since they will mutate most frequently
COPY resources/ /app/resources/
COPY metrics.json /app/metrics.json

FROM agent-machine
WORKDIR /app
RUN addgroup --system --gid 1001 eidolon
RUN adduser --system --uid 1001 eidolon

USER eidolon
EXPOSE 8080
ENV PYTHONUNBUFFERED 1
ENTRYPOINT ["eidolon-server"]
CMD ["resources", "--fail-on-bad-agent", "true"]
