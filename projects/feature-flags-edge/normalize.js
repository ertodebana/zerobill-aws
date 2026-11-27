function handler(event) {
  var uri = event.request.uri.toLowerCase();
  if (!/^\/flags\/[a-z0-9-]{1,64}$/.test(uri)) {
    return { statusCode: 404, statusDescription: "Not Found" };
  }
  event.request.uri = uri;
  return event.request;
}
