unit Atlas.IDE.Outline.CrumbProbe;

// Diagnose der Brotkrumenleiste (#1248): warum die Leiste keine Maus
// bekommt. Je Takt prüft Check die Ursache am Fenster der Leiste
// (WindowProblem) und, solange keine vorliegt, welches Fenster unter der Maus
// über der Leiste liegt (HitProblem). Beides einmal je Wechsel mit
// Elternkette ins Protokoll; danach als Netz die Leiste wieder bedienbar
// machen. Abgetrennt vom Stand der Brotkrumen (TBreadcrumbsState), der den
// Pfad zeigt; hier steht nur, was zuletzt protokolliert ist.
// Nur im Hauptthread.

interface

uses
  Winapi.Windows,
  Atlas.UI.Outline.Breadcrumbs;

type
  TAtlasIdeCrumbProbe = class
  private
    /// <summary>Fenster, das zuletzt unter der Maus über der Leiste lag.</summary>
    FProbed: HWND;
    /// <summary>Zuletzt protokollierte Ursache am Fenster der Leiste ('' = keine).</summary>
    FProblem: string;
  public
    /// <summary>Diagnose, warum die Leiste keine Maus bekommt. Die Ursache am Fenster der Leiste (WindowProblem:
    /// anderer Thread, falsches Elternfenster, gesperrt, ausgeblendet) prüft jeder Takt, nicht erst das Überfahren;
    /// landet die Maus über der Leiste bei einem anderen Fenster desselben Formulars, nennt HitProblem die Ursache am
    /// Mauspunkt (Region, HTTRANSPARENT, Geschwister darüber). Beides einmal je Wechsel mit Eltern- kette
    /// protokollieren. Netz, nicht Ursache: Danach wird die Leiste wieder bedienbar gemacht (freigeben, zeigen, neu
    /// anlegen, nach vorn holen), bis das Protokoll den Verursacher nennt und er an der Wurzel behoben ist. Die
    /// Einfügereihenfolge ist es nicht: Im Protokoll vom 21.10. lag die Leiste mit alTop bei 0,0 und kein Geschwister
    /// darüber, die Maus landete beim Elternfenster „EditorPanel“ selbst.</summary>
    procedure Check(ABar: TAtlasBreadcrumbBar);
  end;

implementation

uses
  System.SysUtils,
  System.Types,
  Vcl.Controls,
  Atlas.Core.Diagnostics.Guard,
  Atlas.IDE.Foundation.EditorWindows;

const
  // Texte des Protokolls (Diagnose, nicht übersetzt wie die übrigen Einträge von TAtlasGuard.Log).
  cNotAncestor = 'kein Vorfahr; hole die Leiste nach vorn';
  cAncestor = 'Vorfahr der Leiste; lege die Leiste neu an';
  cNoCause = 'am Fenster der Leiste keine erkennbar';

/// <summary>Netz (siehe Probe) für eine Ursache am Fenster der Leiste: freigeben, freischalten, zeigen. Ein
/// Fenster eines fremden Threads lässt sich von hier nicht zerstören (DestroyWindow schlägt fehl); dann nur
/// protokollieren, damit die Ursache feststeht.</summary>
procedure RepairBar(ABar: TAtlasBreadcrumbBar);
begin
  if GetWindowThreadProcessId(ABar.Handle, nil) <> MainThreadID then
  begin
    Exit;
  end;
  if (ABar.Parent = nil) or not ABar.Parent.HandleAllocated or (GetParent(ABar.Handle) <> ABar.Parent.Handle) then
  begin
    ABar.Free;
    Exit;
  end;
  if not IsWindowEnabled(ABar.Handle) then
  begin
    ABar.Enabled := True;
    EnableWindow(ABar.Handle, True);
  end;
  if GetWindowLongPtr(ABar.Handle, GWL_STYLE) and WS_VISIBLE = 0 then
  begin
    ShowWindow(ABar.Handle, SW_SHOWNA);
  end;
end;

/// <summary>Fenster AWindow liegt unter der Maus ACursor über der Leiste: Ursache protokollieren, dann Netz (siehe
/// Probe): Vorfahren legen die Leiste neu an, sonst kommt sie nach vorn.</summary>
procedure ReportCover(ABar: TAtlasBreadcrumbBar; AWindow: HWND; const ACursor: TPoint);
var
  mWindowClass: array[0..255] of Char;
  mControl: TWinControl;
  mName, mRelation, mCause: string;
  mAncestor: Boolean;
begin
  mWindowClass[0] := #0;
  GetClassName(AWindow, mWindowClass, Length(mWindowClass));
  mControl := FindControl(AWindow);
  mName := '';
  if mControl <> nil then
  begin
    mName := TAtlasIdeEditorWindows.ParentChain(mControl);
  end;
  mAncestor := IsChild(AWindow, ABar.Handle);
  mRelation := cNotAncestor;
  if mAncestor then
  begin
    mRelation := cAncestor;
  end;
  mCause := ABar.HitProblem(ACursor);
  if mCause = '' then
  begin
    mCause := cNoCause;
  end;
  TAtlasGuard.Log(Format('Brotkrumen: Maus landet bei %s (%s, %s) statt bei der Leiste (in %s); Ursache: %s',
    [string(mWindowClass), mName, mRelation, TAtlasIdeEditorWindows.ParentChain(ABar.Parent), mCause]));
  if mAncestor then
  begin
    ABar.Free;
    Exit;
  end;
  ABar.BringToFront;
end;

/// <summary>Fenster unter der Maus über ABar prüfen, einmal je Wechsel (AProbed); Maus weg setzt AProbed zurück,
/// damit dasselbe Fenster beim nächsten Mal wieder protokolliert und behoben wird.</summary>
procedure ProbeMouse(ABar: TAtlasBreadcrumbBar; var AProbed: HWND);
var
  mCursor: TPoint;
  mWindow: HWND;
begin
  if not GetCursorPos(mCursor) or not PtInRect(ABar.ClientRect, ABar.ScreenToClient(mCursor)) then
  begin
    AProbed := 0;
    Exit;
  end;
  mWindow := WindowFromPoint(mCursor);
  if mWindow = AProbed then
  begin
    Exit;
  end;
  AProbed := mWindow;
  if mWindow = ABar.Handle then
  begin
    TAtlasGuard.Log('Brotkrumen: Maus kommt an der Leiste an');
  end
  // Ein Fenster eines anderen Formulars (Dialog, Popup) liegt zu Recht darüber.
  else if GetAncestor(mWindow, GA_ROOT) = GetAncestor(ABar.Handle, GA_ROOT) then
  begin
    ReportCover(ABar, mWindow, mCursor);
  end;
end;

{ TAtlasIdeCrumbProbe }

procedure TAtlasIdeCrumbProbe.Check(ABar: TAtlasBreadcrumbBar);
var
  mBar: TAtlasBreadcrumbBar;
  mProblem: string;
begin
  mBar := ABar;
  if (mBar = nil) or not mBar.HandleAllocated or not mBar.Showing then
  begin
    Exit;
  end;
  mProblem := mBar.WindowProblem;
  if (mProblem <> FProblem) and (mProblem <> '') then
  begin
    TAtlasGuard.Log(Format('Brotkrumen: %s (in %s)', [mProblem, TAtlasIdeEditorWindows.ParentChain(mBar.Parent)]));
  end;
  FProblem := mProblem;
  if mProblem <> '' then
  begin
    RepairBar(mBar);
  end
  else
  begin
    ProbeMouse(mBar, FProbed);
  end;
end;

end.
