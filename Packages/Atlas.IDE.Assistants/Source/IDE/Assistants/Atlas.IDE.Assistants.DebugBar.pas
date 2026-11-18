unit Atlas.IDE.Assistants.DebugBar;

// Leiste „KI-Assistent debuggt“ im Editorfenster (#1874) über TAtlasEditorBarHost: oben neben dem Code-Editor,
// solange ein KI-Assistent eine Sitzung steuert oder „Pause für KI“ gilt und debug.mcp.banner an ist
// (TAtlasDebugGate.BarShown). Die Knöpfe gehen an den Eingang: „Pause für KI“/„Fortsetzen“ an SetPaused,
// „Übernehmen“ an TakeOver. Refresh ruft der Eingang bei jeder Änderung, das Modul nach Einstellungen und Thema.

interface

uses
  System.SysUtils,
  Vcl.Controls,
  Atlas.UI.Assistants.DebugBar,
  Atlas.IDE.Foundation.EditorBarHost,
  Atlas.IDE.Assistants.DebugInbox;

type
  TAtlasIdeAssistantDebugBar = class
  private
    FHost: TAtlasEditorBarHost;
    FInbox: TFunc<TAtlasIdeDebugInbox>;
    FBanner: TFunc<Boolean>;
    function CreateBar: TControl;
    procedure Clicked(AButton: TAtlasAssistantDebugButton);
  public
    /// <summary>AInbox liefert den Eingang (nil, solange er nicht läuft), ABanner die Einstellung
    /// debug.mcp.banner.</summary>
    constructor Create(const AInbox: TFunc<TAtlasIdeDebugInbox>; const ABanner: TFunc<Boolean>);
    destructor Destroy; override;
    /// <summary>Text der Leiste aus dem Zustand des Eingangs.</summary>
    class function ViewOf(AInbox: TAtlasIdeDebugInbox): TAtlasAssistantDebugView; static;
    /// <summary>Leisten zeigen, auffrischen oder entfernen.</summary>
    procedure Refresh;
    procedure ApplyTheme;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Style.Palette,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.UI.Assistants.Strings;

var
  /// <summary>Die lebende Leiste; eingereihte Klicks prüfen, ob es sie noch gibt.</summary>
  GCurrent: TAtlasIdeAssistantDebugBar;

{ TAtlasIdeAssistantDebugBar }

constructor TAtlasIdeAssistantDebugBar.Create(const AInbox: TFunc<TAtlasIdeDebugInbox>;
  const ABanner: TFunc<Boolean>);
begin
  inherited Create;
  FInbox := AInbox;
  FBanner := ABanner;
  FHost := TAtlasEditorBarHost.Create('KI-Debuggen', TAtlasFeature.Debugger,
    function(AEditorParent: TWinControl): TControl
    begin
      Result := CreateBar;
    end, nil);
  FHost.Placement.DockTop;
  FHost.Placement.ShowIn := TAtlasEditorBarView.Code;
  GCurrent := Self;
end;

destructor TAtlasIdeAssistantDebugBar.Destroy;
begin
  if GCurrent = Self then
  begin
    GCurrent := nil;
  end;
  FreeAndNil(FHost);
  FInbox := nil;
  FBanner := nil;
  inherited Destroy;
end;

function TAtlasIdeAssistantDebugBar.CreateBar: TControl;
var
  mBar: TAtlasAssistantDebugBar;
  mHost: TAtlasEditorBarHost;
begin
  mBar := TAtlasAssistantDebugBar.Create(nil);
  mHost := FHost;
  mBar.SetColors(TAtlasIdeStyle.BarColors);
  mBar.SetView(ViewOf(FInbox()));
  mBar.OnButton :=
    procedure(AButton: TAtlasAssistantDebugButton)
    begin
      Clicked(AButton);
    end;
  mBar.OnDisabled :=
    procedure(ASender: TObject)
    begin
      mHost.Disabled(ASender);
    end;
  Result := mBar;
end;

class function TAtlasIdeAssistantDebugBar.ViewOf(AInbox: TAtlasIdeDebugInbox): TAtlasAssistantDebugView;
var
  mClient: string;
begin
  Result := Default(TAtlasAssistantDebugView);
  if AInbox = nil then
  begin
    Exit;
  end;
  mClient := AInbox.Gate.Client;
  if mClient = '' then
  begin
    mClient := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.DebugBarClient);
  end;
  if AInbox.Gate.Paused then
  begin
    Result.Text := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.DebugBarPausedText);
    Result.PauseCaption := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.DebugBarResume);
    Result.PauseHint := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.DebugBarResumeHint);
  end
  else
  begin
    Result.Text := TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.DebugBarText,
      [mClient, AInbox.Gate.Steps, AInbox.Gate.LastTool]);
    Result.PauseCaption := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.DebugBarPause);
    Result.PauseHint := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.DebugBarPauseHint);
  end;
  Result.TakeOverCaption := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.DebugBarTakeOver);
  Result.TakeOverHint := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.DebugBarTakeOverHint);
  Result.CanTakeOver := AInbox.Gate.Own;
end;

procedure TAtlasIdeAssistantDebugBar.Clicked(AButton: TAtlasAssistantDebugButton);
var
  mOwner: TAtlasIdeAssistantDebugBar;
begin
  // Eingereiht: Der Klick kann die Leiste entfernen (Übernehmen), sie steht aber noch in ihrem MouseUp.
  mOwner := Self;
  TAtlasMainThread.ForceQueue(TAtlasFeature.Debugger,
    procedure
    var
      mInbox: TAtlasIdeDebugInbox;
    begin
      if GCurrent <> mOwner then
      begin
        Exit;
      end;
      mInbox := mOwner.FInbox();
      if mInbox = nil then
      begin
        Exit;
      end;
      if AButton = TAtlasAssistantDebugButton.Pause then
      begin
        mInbox.SetPaused(not mInbox.Gate.Paused);
      end
      else
      begin
        mInbox.TakeOver;
      end;
    end);
end;

procedure TAtlasIdeAssistantDebugBar.Refresh;
var
  mInbox: TAtlasIdeDebugInbox;
  mView: TAtlasAssistantDebugView;
begin
  mInbox := FInbox();
  if (mInbox = nil) or not mInbox.Gate.BarShown(FBanner()) then
  begin
    FHost.Clear;
    Exit;
  end;
  if not FHost.Guard then
  begin
    Exit;
  end;
  FHost.Ensure;
  mView := ViewOf(mInbox);
  FHost.ForEach(
    procedure(ABar: TControl)
    begin
      TAtlasAssistantDebugBar(ABar).SetView(mView);
    end);
end;

procedure TAtlasIdeAssistantDebugBar.ApplyTheme;
var
  mColors: TAtlasColors;
begin
  mColors := TAtlasIdeStyle.BarColors;
  FHost.ForEach(
    procedure(ABar: TControl)
    begin
      TAtlasAssistantDebugBar(ABar).SetColors(mColors);
      ABar.Invalidate;
    end);
end;

end.
