#Requires AutoHotkey v2.0
#SingleInstance Force

; ==============================================
;  AutoResources
; ----------------------------------------------
;   @name: AutoResources.ahk
;   @description: Automatiza el farmeo de materiales Life Skill.
;   @author: Joseleelsuper
;   @bpsr_guild: HusaresAlados [1818]
;   @use
;       - Pulsa F8 para activar/desactivar la automatización de recursos Focused.
;       - Pulsa F9 para activar/desactivar la automatización.
;       - Pulsa F10 para detener el script completamente.
;       - El script detecta el color blanco en coordenadas específicas
;         y realiza Alt+Click automáticamente.
; ==============================================

CoordMode("Pixel", "Screen")
CoordMode("Mouse", "Screen")

; ----------------------------
;  Configuración y Estado
; ----------------------------
global Config := {}
global State := {}

; ============================
;  Inicialización
; ============================
Init() {
    global Config, State

    ; -- Parámetros base de referencia
    Config.Base := { w: 1920, h: 1080 }

    ; -- Temporizadores y tolerancias
    Config.TimerInterval := 20            ; ms entre ciclos de comprobación
    Config.Tolerance := { primary: 15 }   ; tolerancia para color blanco

    ; -- Tiempos de espera (centralizados)
    Config.Timings := {}
    Config.Timings.clickDelay := 50       ; espera antes/después de clicks
    Config.Timings.afterClick := 200      ; espera tras ejecutar Alt+Click
    Config.Timings.cooldown := 5000       ; cooldown de 5 segundos entre clicks

    ; -- Colores objetivo (0xRRGGBB)
    Config.Colors := { white: 0xFFFFFF }  ; Blanco puro

    ; -- Lista de posibles ejecutables del juego
    Config.GameWindowExecutables := ["BPSR_STEAM.exe", "BPSR_EPIC.exe", "BPSR.exe", "BPSR"]

    ; -- Coordenadas base (en 1920x1080). Todas se escalarán al iniciar.
    ; Ahora usamos áreas rectangulares en lugar de puntos individuales
    Config.AreasBase := Map()
    ; Target2 F8 (Focused): área rectangular
    Config.AreasBase["target2"] := { x1: 1411, y1: 555, x2: 1440, y2: 586 }
    ; Target F9 (Normal): área rectangular
    Config.AreasBase["target"] := { x1: 1411, y1: 628, x2: 1440, y2: 655 }

    ; -- Flag para habilitar/deshabilitar logs (ANTES de DetectGameWindow)
    Config.LoggingEnabled := true
    ; -- Ruta de log
    Config.LogPath := A_ScriptDir . "\AutoResources.log"

    ; -- Detectar ventana del juego y obtener dimensiones
    DetectGameWindow()

    ; -- Calcular escala basada en el tamaño de la ventana del juego
    Config.Scale := { x: (Config.GameWindow.w + 0.0) / Config.Base.w, y: (Config.GameWindow.h + 0.0) / Config.Base.h }

    ; -- Precalcular áreas escaladas relativas a la ventana del juego
    Config.Areas := Map()
    for key, area in Config.AreasBase {
        sx1 := Round(area.x1 * Config.Scale.x) + Config.GameWindow.x
        sy1 := Round(area.y1 * Config.Scale.y) + Config.GameWindow.y
        sx2 := Round(area.x2 * Config.Scale.x) + Config.GameWindow.x
        sy2 := Round(area.y2 * Config.Scale.y) + Config.GameWindow.y
        Config.Areas[key] := { x1: sx1, y1: sy1, x2: sx2, y2: sy2 }
    }

    ; -- Estado en memoria
    State.toggle := false          ; Automatización activa/inactiva (F9)
    State.toggle2 := false         ; Automatización activa/inactiva (F8)
    State.origX := 0               ; Posición original del ratón (X)
    State.origY := 0               ; Posición original del ratón (Y)
    State.lastClickTime := Map()   ; Último tiempo de click para cada target
    State.lastClickTime["target"] := 0
    State.lastClickTime["target2"] := 0

    Log("INFO", "Init completado | Ventana del juego: " . Config.GameWindow.w . "x" . Config.GameWindow.h . " en (" .
        Config.GameWindow.x . "," . Config.GameWindow.y . ") | ScaleX=" . Config.Scale.x . ", ScaleY=" . Config.Scale.y
    )
}

; Detecta la ventana del juego y guarda su posición y tamaño
DetectGameWindow() {
    global Config

    hwnd := 0
    detectedExe := ""

    ; Intentar detectar la ventana con cada ejecutable posible
    for index, exeName in Config.GameWindowExecutables {
        try {
            hwnd := WinGetID("ahk_exe " . exeName)
            if (hwnd) {
                detectedExe := exeName
                Log("INFO", "Ventana del juego encontrada: " . exeName)
                break
            }
        }
    }

    if (hwnd) {
        ; Obtener posición y tamaño de la ventana
        WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " . hwnd)

        ; Obtener el área cliente (sin bordes de ventana)
        rect := Buffer(16, 0)
        DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rect)
        clientW := NumGet(rect, 8, "Int")
        clientH := NumGet(rect, 12, "Int")

        ; Obtener offset del área cliente respecto a la ventana
        point := Buffer(8, 0)
        DllCall("ClientToScreen", "Ptr", hwnd, "Ptr", point)
        clientX := NumGet(point, 0, "Int")
        clientY := NumGet(point, 4, "Int")

        Config.GameWindow := { x: clientX, y: clientY, w: clientW, h: clientH, exe: detectedExe }
        Log("INFO", "Ventana del juego detectada (" . detectedExe . "): " . clientW . "x" . clientH . " en posición (" .
            clientX . "," . clientY . ")")
    } else {
        ; Si no se encuentra ninguna ventana, usar pantalla completa como fallback
        Config.GameWindow := { x: 0, y: 0, w: A_ScreenWidth, h: A_ScreenHeight, exe: "ninguno" }

        ; Construir lista de ejecutables buscados para el mensaje de log
        exeList := ""
        for index, exeName in Config.GameWindowExecutables {
            exeList .= exeName
            if (index < Config.GameWindowExecutables.Length)
                exeList .= ", "
        }

        Log("WARN", "No se detectó la ventana del juego. Ejecutables buscados: " . exeList .
            " -> Usando pantalla completa como fallback")
    }
}

; Ejecutar inicialización al cargar el script
Init()

; Registrar manejador de salida
OnExit(OnExitHandler)

; ============================
;  Hotkeys de activación
; ============================
F9:: {
    ToggleTarget("target", "toggle")
}

F8:: {
    ToggleTarget("target2", "toggle2")
}

ToggleTarget(targetName, stateVar) {
    global Config, State
    State.%stateVar% := !State.%stateVar%
    if (State.%stateVar%) {
        Log("INFO", "Toggle " . targetName . " ON -> Iniciando timer (" . Config.TimerInterval . " ms)")
        ; Crear función anónima que captura el targetName
        timerFunc := () => CheckPixelsLogic(targetName)
        State.%stateVar%Timer := timerFunc
        SetTimer(timerFunc, Config.TimerInterval)
    } else {
        Log("INFO", "Toggle " . targetName . " OFF -> Deteniendo timer")
        SetTimer(State.%stateVar%Timer, 0)
        SafeReleaseAll()
    }
}

; ============================
;  Bucle principal
; ============================
CheckPixelsLogic(targetName) {
    global Config, State

    ; -- Verificar cooldown
    currentTime := A_TickCount
    timeSinceLastClick := currentTime - State.lastClickTime[targetName]

    if (timeSinceLastClick < Config.Timings.cooldown) {
        ; Aún en cooldown, no hacer nada
        return
    }

    ; -- Buscar color blanco dentro del área rectangular
    area := Config.Areas[targetName]
    foundPixel := FindWhitePixelInArea(area)

    ; -- Si detecta color blanco, ejecutar Alt+Click
    if (foundPixel) {
        Log("INFO", "Color blanco detectado en " . targetName . " en (" . foundPixel.x . ", " . foundPixel.y .
            ") -> Ejecutando Alt+Click")

        ; Guardar posición actual del ratón
        SaveMousePositionOnce()

        ; Realizar Alt+Click (mantener Alt presionado durante el click)
        Send("{Alt down}")
        Sleep(50)
        Click(foundPixel.x . " " . foundPixel.y)
        Sleep(50)
        Send("{Alt up}")

        Log("INFO", "Alt+Click ejecutado en " . targetName . " (" . foundPixel.x . ", " . foundPixel.y . ")")

        ; Actualizar tiempo del último click
        State.lastClickTime[targetName] := A_TickCount

        ; Restaurar posición del ratón
        Sleep(Config.Timings.afterClick)
        RestoreMousePosition()
    }
}

; ============================
;  Utilidades (globales)
; ============================

; Guarda la posición del ratón sólo una vez (si no se ha guardado).
SaveMousePositionOnce() {
    global State
    if (State.origX = 0 && State.origY = 0) {
        MouseGetPos(&_x, &_y)
        State.origX := _x
        State.origY := _y
        Log("DEBUG", "Posición original guardada: x=" . State.origX . ", y=" . State.origY)
    }
}

; Restaura la posición del ratón si existe una almacenada.
RestoreMousePosition() {
    global State
    if (State.origX || State.origY) {
        MouseMove(State.origX, State.origY, 0)
        State.origX := 0
        State.origY := 0
        Log("DEBUG", "Posición del ratón restaurada")
    }
}

; Busca un píxel blanco dentro de un área rectangular.
; Devuelve {x, y} si encuentra uno, o false si no.
FindWhitePixelInArea(area) {
    global Config

    ; Iterar por cada píxel del área
    loop area.y2 - area.y1 + 1 {
        y := area.y1 + A_Index - 1
        loop area.x2 - area.x1 + 1 {
            x := area.x1 + A_Index - 1
            color := GetColorAtXY(x, y)
            if (ColorCloseEnough(color, Config.Colors.white, Config.Tolerance.primary)) {
                return { x: x, y: y }
            }
        }
    }
    return false
}

; Obtiene el color en un punto (objeto {x,y}). Devuelve 0xRRGGBB.
GetColorAtPoint(pt) {
    return GetColorAtXY(pt.x, pt.y)
}

GetColorAtXY(x, y) {
    return PixelGetColor(x, y, "RGB")
}

; Comparación de colores con tolerancia por canal (R, G, B).
ColorCloseEnough(color1, color2, tolerance := 10) {
    c1r := (color1 >> 16) & 0xFF
    c1g := (color1 >> 8) & 0xFF
    c1b := color1 & 0xFF
    c2r := (color2 >> 16) & 0xFF
    c2g := (color2 >> 8) & 0xFF
    c2b := color2 & 0xFF
    return (Abs(c1r - c2r) <= tolerance
    && Abs(c1g - c2g) <= tolerance
    && Abs(c1b - c2b) <= tolerance)
}

; Libera todos los recursos de estado al desactivar.
SafeReleaseAll() {
    global State
    RestoreMousePosition()
    Log("INFO", "SafeReleaseAll: estado limpiado")
}

F10:: {
    Log("EXIT", "F10 presionado -> Saliendo")
    ; Detener todos los timers activos
    if (State.HasOwnProp("toggleTimer"))
        SetTimer(State.toggleTimer, 0)
    if (State.HasOwnProp("toggle2Timer"))
        SetTimer(State.toggle2Timer, 0)
    SafeReleaseAll()
    ExitApp()
}

; ============================
;  Sistema de Logs
; ============================

Log(type, msg) {
    global Config
    if (!Config.LoggingEnabled)
        return
    type := StrUpper(type)
    _date := FormatTime(, "yy-MM-dd")
    _time := FormatTime(, "HH:mm:ss")
    line := "[" . _date . "] [" . _time . "] [" . type . "] <" . msg . ">`r`n"
    FileAppend(line, Config.LogPath, "UTF-8")
}

OnExitHandler(ExitReason, ExitCode) {
    Log("EXIT", "OnExit -> Razón=" . ExitReason)
}
