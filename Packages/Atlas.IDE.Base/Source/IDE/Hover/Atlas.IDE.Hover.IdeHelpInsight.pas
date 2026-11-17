unit Atlas.IDE.Hover.IdeHelpInsight;

// Blendet das Help-Insight-Fenster der IDE aus, solange Atlas den Tooltip
// selbst zeigt (Entscheidung in Atlas.Core.Hover.IdeHelpInsight). Ein
// WinEvent-Haken nur für diesen Prozess meldet jedes Fenster, das sichtbar
// wird; ist es THelpInsightWindowImpl, wird es wieder versteckt. Die IDE
// zeigt es beim nächsten Hinweis erneut, der Haken versteckt es dann wieder.
// Über die Registry geht es nicht: Delphi 12 merkt sich die Code-Insight-
// Schalter eines fremden Managers nicht und beginnt jeden Start mit „an“.
// Es gibt nur einen Wächter; der Haken endet mit Destroy, danach erreicht
// kein Ereignis mehr Atlas.

interface

uses
  System.SysUtils;

type
  TAtlasIdeHelpInsightGuard = class
  private
    FHook: THandle;
    FOwnTooltip: TFunc<Boolean>;
    FHandlesTopFile: TFunc<Boolean>;
  public
    /// <summary>Haken anlegen; nur im Hauptthread. AOwnTooltip: zeigt Atlas den Tooltip selbst? AHandlesTopFile:
    /// bedient Atlas die Datei im obersten Editor?</summary>
    constructor Create(const AOwnTooltip, AHandlesTopFile: TFunc<Boolean>);
    destructor Destroy; override;
    /// <summary>Fenster AWindow ausblenden, wenn es das Help-Insight-Fenster ist und der Atlas-Tooltip gilt.</summary>
    procedure WindowShown(AWindow: THandle);
  end;

implementation

uses
  Winapi.Windows,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Hover.IdeHelpInsight;

const
  // Fehlen in älteren Fassungen von Winapi.Windows; selbst deklariert.
  cEventObjectShow = $8002;
  cWinEventOutOfContext = 0;
  cObjIdWindow = 0;

type
  TAtlasWinEventProc = procedure(AHook: THandle; AEvent: DWORD; AWindow: HWND; AObject, AChild: Longint;
    AThread, ATime: DWORD); stdcall;

function AtlasSetWinEventHook(AEventMin, AEventMax: DWORD; AModule: HMODULE; ACallback: TAtlasWinEventProc;
  AProcessId, AThreadId, AFlags: DWORD): THandle; stdcall; external user32 name 'SetWinEventHook';
function AtlasUnhookWinEvent(AHook: THandle): BOOL; stdcall; external user32 name 'UnhookWinEvent';

var
  // Der eine Wächter; nil, sobald er abgebaut ist (späte Ereignisse laufen dann ins Leere).
  Guard: TAtlasIdeHelpInsightGuard;

// Die Signatur gibt WINEVENTPROC von Windows vor.
// lsp-ignore: metric-parameter-count
procedure WinEventShown(AHook: THandle; AEvent: DWORD; AWindow: HWND; AObject, AChild: Longint;
  AThread, ATime: DWORD); stdcall;
begin
  if (AObject = cObjIdWindow) and (AChild = 0) and (AWindow <> 0) and (Guard <> nil) then
  begin
    Guard.WindowShown(AWindow);
  end;
end;

function WindowClassName(AWindow: THandle): string;
var
  mBuffer: array[0..255] of Char;
  mLength: Integer;
begin
  mLength := GetClassName(AWindow, mBuffer, Length(mBuffer));
  SetString(Result, mBuffer, mLength);
end;

{ TAtlasIdeHelpInsightGuard }

constructor TAtlasIdeHelpInsightGuard.Create(const AOwnTooltip, AHandlesTopFile: TFunc<Boolean>);
begin
  inherited Create;
  FOwnTooltip := AOwnTooltip;
  FHandlesTopFile := AHandlesTopFile;
  if Guard = nil then
  begin
    Guard := Self;
    // Außerhalb des Kontexts: Die Meldung kommt über die Nachrichtenschleife des Hauptthreads.
    FHook := AtlasSetWinEventHook(cEventObjectShow, cEventObjectShow, 0, WinEventShown, GetCurrentProcessId, 0,
      cWinEventOutOfContext);
  end;
end;

destructor TAtlasIdeHelpInsightGuard.Destroy;
begin
  if Guard = Self then
  begin
    Guard := nil;
  end;
  if FHook <> 0 then
  begin
    AtlasUnhookWinEvent(FHook);
    FHook := 0;
  end;
  FOwnTooltip := nil;
  FHandlesTopFile := nil;
  inherited Destroy;
end;

procedure TAtlasIdeHelpInsightGuard.WindowShown(AWindow: THandle);
var
  mClass: string;
begin
  try
    // Zuerst die Klasse: Jedes Fenster der IDE, das sichtbar wird, kommt hier vorbei.
    mClass := WindowClassName(AWindow);
    if not TAtlasIdeHelpInsight.IsHelpInsightWindow(mClass) or TAtlasGuard.Disabled(TAtlasFeature.Hover) or
      not Assigned(FOwnTooltip) or not Assigned(FHandlesTopFile) then
    begin
      Exit;
    end;
    if TAtlasIdeHelpInsight.ShouldHide(mClass, FOwnTooltip(), FHandlesTopFile()) then
    begin
      ShowWindow(AWindow, SW_HIDE);
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Hover, E);
  end;
end;

end.
