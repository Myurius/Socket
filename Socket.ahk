/************************************************************************
 * @description A simple socket class with a server, and client.
 * @author @Myurius
 * @date 2025/04/27
 * @version 0.0.3.1
 **********************************************************************
 */

class Socket {
    static __New() {
        #DllLoad "ws2_32.dll"
        WSAData := Buffer(394 + A_PtrSize)
        if err := DllCall("Ws2_32\WSAStartup", "ushort", 0x0202, "ptr", WSAData.Ptr)
            throw OSError(err)
        if NumGet(WSAData, 2, "ushort") != 0x0202
            throw Error("Winsock version 2.2 not available", -1)  
    }

    static WM_SOCKET := 0x5990
    static FD_READ => 0x01
    static FD_ACCEPT => 0x08
    static FD_CLOSE => 0x20 

    AsyncSelect(Event) {
        if DllCall("ws2_32\WSAAsyncSelect", "ptr", this._sock, "ptr", A_ScriptHwnd, "uint", Socket.WM_SOCKET, "uint", Event)
            throw OSError(DllCall("ws2_32\WSAGetLastError"))
        OnMessage(Socket.WM_SOCKET, this.OnMessage.Bind(this))
    }

    OnMessage(wParam, lParam, msg, hWnd) {
        if msg != Socket.WM_SOCKET
            return
        if lParam & Socket.FD_ACCEPT && this._eventobj.HasMethod("Accept")
            (this._eventobj.Accept)(this)
        if lParam & Socket.FD_CLOSE && this._eventobj.HasMethod("Close")
            (this._eventobj.Close)(this)
        if lParam & Socket.FD_READ && this._eventobj.HasMethod("Receive")
            (this._eventobj.Receive)(this)
    }

    Close() {
        if (this._connected = 0) || (this._closed = 1)
            return
        
        if this is Socket.Client
            if DllCall("ws2_32\shutdown", "ptr", this._sock, "int", 2) = -1
                throw OSError(DllCall("ws2_32\WSAGetLastError"))
        if DllCall("ws2_32\closesocket", "ptr", this._sock) = -1
            throw OSError(DllCall("ws2_32\WSAGetLastError"))
        this._closed := 1
    }

    createsockaddr(host, port) {
        sockaddr := Buffer(16)
        NumPut("ushort", 2, sockaddr, 0)
        NumPut("ushort", DllCall("ws2_32\htons", "ushort", Port), sockaddr, 2)
        NumPut("uint", host, sockaddr, 4)
        return sockaddr
    }

    class Server extends Socket {
        _closed := 0
        _connected := 0
        __New(EventObject, Sock := -1) {
            this._sock := Sock
            this._eventobj := EventObject
            OnExit((*) => (DllCall("ws2_32\WSACleanup")))
        }

        Bind(Host, Port) {
            if this._sock != -1
                throw Error("Socket already exists", -1)
            
            if (this._sock := DllCall("ws2_32\socket", "int", 2, "int", 1, "int", 6)) = -1
                throw OSError(DllCall("ws2_32\WSAGetLastError"))
            if (h := DllCall("ws2_32\inet_addr", "astr", Host)) = -1
                throw Error("Invalid IP", -1)

            sockaddr := this.createsockaddr(h, port)

            if DllCall("ws2_32\bind", "ptr", this._sock, "ptr", sockaddr.Ptr, "int", sockaddr.Size) = -1
                throw OSError(DllCall("ws2_32\WSAGetLastError"))
            this._connected := 1
        }

        Listen(Backlog := 10) {
            if DllCall("ws2_32\listen", "ptr", this._sock, "int", Backlog) = -1
                throw OSError(DllCall("ws2_32\WSAGetLastError"))
            ev := (Socket.FD_ACCEPT | Socket.FD_CLOSE)
            this.AsyncSelect(ev)
        }

        Accept() {
            if !(sock := DllCall("ws2_32\accept", "ptr", this._sock, "ptr", 0, "ptr", 0))
                if (err := DllCall("ws2_32\WSAGetLastError")) != 10035 ;WSAEWOULDBLOCK
                    throw OSError(err)
            return sock
        }
    }
    class Client extends Socket {
        _closed := 0
        _connected := 0
        __New(EventObject, Sock := -1) {
            this._sock := Sock
            this._eventobj := EventObject
            if Sock != -1
                this.AsyncSelect(Socket.FD_READ)
            OnExit((*) => (this.Close(), DllCall("ws2_32\WSACleanup")))
        }

        Connect(Host, Port) {
            if this._sock != -1
                throw Error("Socket already exists", -1)
            
            if (this._sock := DllCall("ws2_32\socket", "int", 2, "int", 1, "int", 6)) = -1
                throw OSError(DllCall("ws2_32\WSAGetLastError"))
            if (h := DllCall("ws2_32\inet_addr", "astr", Host)) = -1
                throw Error("Invalid IP", -1)

            sockaddr := this.createsockaddr(h, port)

            if DllCall("ws2_32\connect", "ptr", this._sock, "ptr", sockaddr.Ptr, "int", sockaddr.Size) = -1
                throw OSError(DllCall("ws2_32\WSAGetLastError"))
            this.AsyncSelect((Socket.FD_CLOSE | Socket.FD_READ))
            this._connected := 1
        }

        Receive(Buf) {
            s := DllCall("ws2_32\recv", "ptr", this._sock, "ptr", Buf.Ptr, "int", Buf.Size, "int", 0)
            if s = -1
                if (err := DllCall("ws2_32\WSAGetLastError")) != 10035 ;WSAEWOULDBLOCK
                    throw OSError(err)
            return s
        }

        Send(Buf) {
            if DllCall("ws2_32\send", "ptr", this._sock, "ptr", Buf.Ptr, "int", Buf.Size, "int", 0) = -1
                if (err := DllCall("ws2_32\WSAGetLastError")) != 10035 ;WSAEWOULDBLOCK
                    throw OSError(err)
        }

        CreateMessageBuffer(Message, Encoding := "UTF-8") {
            buf := Buffer(StrPut(Message, Encoding))
            StrPut(Message, buf, Encoding)
            return buf
        }
    }
}
