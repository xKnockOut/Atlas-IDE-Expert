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
// Grenzen: Der Haken läuft außerhalb des Kontexts, das Fenster wird also erst
// nach dem Anzeigen versteckt und kann kurz aufblitzen. Entschieden wird nach
// der Datei im Editor unter der Maus (MouseOver aus dem Hover), sonst nach dem
// obersten Editor. Scheitert SetWinEventHook, oder erscheint das Fenster in
// einer Sitzung mit Atlas-Tooltip nie (Klasse umbenannt), steht das im
// Protokoll; der Wächter wirkt dann nicht.

interface

uses
  System.SysUtils;

type
  TAtlasIdeHelpInsightGuard = class
  private
    FHook: THandle;
    FOwnTooltip: TFunc<Boolean>;
    FTopFile: TFunc<string>;
    FHandles: TFunc<string, Boolean>;
    FMouseFile: string;
    FSeen: Boolean;
  public
    /// <summary>Haken anlegen; nur im Hauptthread. AOwnTooltip: zeigt Atlas den Tooltip selbst? ATopFile: Datei im
    /// obersten Editor ('' ohne); AHandles: bedient Atlas diese Datei?</summary>
    constructor Create(const AOwnTooltip: TFunc<Boolean>; const ATopFile: TFunc<string>;
      const AHandles: TFunc<string, Boolean>);
    destructor Destroy; override;
    /// <summary>Die Maus steht im Editor mit AFileName (aus der Mausbewegung des Hovers).</summary>
    procedure MouseOver(const AFileName: string);
    /// <summary>Fenster AWindow ausblenden, wenn es das Help-Insight-Fenster ist und der Atlas-Tooltip gilt.</summary>
    procedure WindowShown(AWindow: THandle);
  end;

implementation

uses
  Winapi.Windows,
  Atlas.Plugin.Diagnostics.Guard,
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

constructor TAtlasIdeHelpInsightGuard.Create(const AOwnTooltip: TFunc<Boolean>; const ATopFile: TFunc<string>;
  const AHandles: TFunc<string, Boolean>);
begin
  inherited Create;
  FOwnTooltip := AOwnTooltip;
  FTopFile := ATopFile;
  FHandles := AHandles;
  if Guard = nil then
  begin
    Guard := Self;
    // Außerhalb des Kontexts: Die Meldung kommt über die Nachrichtenschleife des Hauptthreads.
    FHook := AtlasSetWinEventHook(cEventObjectShow, cEventObjectShow, 0, WinEventShown, GetCurrentProcessId, 0,
      cWinEventOutOfContext);
    if FHook = 0 then
    begin
      TAtlasGuard.Log(Format('Help Insight: SetWinEventHook gescheitert (Fehler %d), ' + // german-ok: Protokoll
        'das Fenster der IDE bleibt neben dem Atlas-Tooltip sichtbar', [GetLastError])); // german-ok: Protokoll
    end;
  end;
end;

destructor TAtlasIdeHelpInsightGuard.Destroy;
begin
  if Guard = Self then
  begin
    Guard := nil;
  end;
  if TAtlasIdeHelpInsight.ReportUnseen(FHook <> 0, FMouseFile <> '', FSeen) then
  begin
    TAtlasGuard.Log('Help Insight: Fenster der Klasse ' + // german-ok: Protokoll
      TAtlasIdeHelpInsight.cWindowClass + ' in dieser Sitzung nie gesehen; ' + // german-ok: Protokoll
      'heißt es in dieser IDE anders, wirkt der Wächter nicht'); // german-ok: Protokoll
  end;
  if FHook <> 0 then
  begin
    AtlasUnhookWinEvent(FHook);
    FHook := 0;
  end;
  FOwnTooltip := nil;
  FTopFile := nil;
  FHandles := nil;
  FMouseFile := '';
  inherited Destroy;
end;

procedure TAtlasIdeHelpInsightGuard.MouseOver(const AFileName: string);
begin
  FMouseFile := AFileName;
end;

procedure TAtlasIdeHelpInsightGuard.WindowShown(AWindow: THandle);
var
  mClass, mFile: string;
begin
  try
    // Zuerst die Klasse: Jedes Fenster der IDE, das sichtbar wird, kommt hier vorbei.
    mClass := WindowClassName(AWindow);
    if not TAtlasIdeHelpInsight.IsHelpInsightWindow(mClass) then
    begin
      Exit;
    end;
    FSeen := True;
    if TAtlasGuard.Disabled(TAtlasFeature.Hover) or not Assigned(FOwnTooltip) or not Assigned(FTopFile) or
      not Assigned(FHandles) then
    begin
      Exit;
    end;
    mFile := TAtlasIdeHelpInsight.FileToDecide(FMouseFile, FTopFile());
    if TAtlasIdeHelpInsight.ShouldHide(mClass, FOwnTooltip(), (mFile <> '') and FHandles(mFile)) then
    begin
      ShowWindow(AWindow, SW_HIDE);
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Hover, E);
  end;
end;

end.
