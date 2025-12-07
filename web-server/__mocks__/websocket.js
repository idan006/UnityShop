export class MockWebSocket {
  constructor(url) {
    this.url = url;
    this.sentMessages = [];
    this.onmessage = null;
    this.onopen = null;
  }

  send(msg) {
    this.sentMessages.push(msg);
  }

  triggerMessage(data) {
    if (this.onmessage) this.onmessage({ data });
  }

  triggerOpen() {
    if (this.onopen) this.onopen();
  }
}

export default MockWebSocket;
