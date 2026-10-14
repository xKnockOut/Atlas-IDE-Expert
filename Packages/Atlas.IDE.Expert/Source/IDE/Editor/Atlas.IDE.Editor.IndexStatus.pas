unit Atlas.IDE.Editor.IndexStatus;

// Fortschritt der Indizierung in der Statusleiste des Editors (#492): Solange
// der Server indiziert, steht rechts in der Statusleiste jedes Editorfensters
// "Atlas indiziert … (n %)"; nie modal, ohne Fokuswechsel. Danach verschwindet
// das Feld wieder. Ein Zeitgeber fragt den Stand zweimal je Sekunde ab und
// ändert die Leiste nur, wenn sich der Text ändert.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.ExtCtrls,
  Vcl.ComCtrls;

type
  TAtlasIndexStatusBar = class
  private
    FTimer: TTimer;
    FText: TFunc<string>;
    FShown: string;
    procedure TimerTick(Sender: TObject);
    procedure Apply(const AText: string);
    procedure ApplyTo(ABar: TStatusBar; const AText: string);
  public
    /// <summary>AText liefert den Stand ('' = nichts läuft), z. B. TLspSession.IndexingText.</summary>
    constructor Create(const AText: TFunc<string>);
    destructor Destroy; override;
  end;

implementation

uses
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard;

const
  // Das eigene Feld erkennt die Klasse an seinem Text (TLspProgress.IndexingTextOf); die Leisten gehören
  // der IDE, ein gemerkter Verweis wäre nach dem Schließen eines Fensters ungültig.
  PanelPrefix = 'Atlas indiziert';
  PanelWidth = 220;

{ TAtlasIndexStatusBar }

constructor TAtlasIndexStatusBar.Create(const AText: TFunc<string>);
begin
  inherited Create;
  FText := AText;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := 500;
  FTimer.OnTimer := TimerTick;
  FTimer.Enabled := True;
end;

destructor TAtlasIndexStatusBar.Destroy;
begin
  FreeAndNil(FTimer);
  try
    Apply('');
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Menu, E);
  end;
  inherited;
end;

procedure TAtlasIndexStatusBar.TimerTick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Menu,
    procedure
    var
      Text: string;
    begin
      Text := '';
      if Assigned(FText) then
        Text := FText();
      // Neue Editorfenster bekommen das Feld beim nächsten Wechsel des Texts.
      if Text = FShown then
        Exit;
      FShown := Text;
      Apply(Text);
    end);
end;

procedure TAtlasIndexStatusBar.Apply(const AText: string);
var
  Services: INTAEditorServices;
  Window: INTAEditWindow;
  Index: Integer;
begin
  if not Supports(BorlandIDEServices, INTAEditorServices, Services) then
    Exit;
  for Index := 0 to Services.EditWindowCount - 1 do
  begin
    Window := Services.EditWindows[Index];
    if (Window <> nil) and (Window.StatusBar <> nil) then
      ApplyTo(Window.StatusBar, AText);
  end;
end;

procedure TAtlasIndexStatusBar.ApplyTo(ABar: TStatusBar; const AText: string);
var
  Index: Integer;
  Panel: TStatusPanel;
begin
  Panel := nil;
  for Index := 0 to ABar.Panels.Count - 1 do
    if ABar.Panels[Index].Text.StartsWith(PanelPrefix) then
      Panel := ABar.Panels[Index];
  if AText = '' then
  begin
    if Panel <> nil then
      ABar.Panels.Delete(Panel.Index);
    Exit;
  end;
  if Panel = nil then
  begin
    Panel := ABar.Panels.Add;
    Panel.Width := PanelWidth;
  end;
  Panel.Text := AText;
end;

end.
