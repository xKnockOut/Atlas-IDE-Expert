unit Atlas.IDE.Debug.ExceptionDialog;

// Den Exception-Dialog der IDE beobachten (#517, #783). Die Open Tools API
// meldet beim Halt wegen einer Exception weder Klasse noch Meldung; der Dialog
// der IDE hat beides. Watch startet nach einem Halt wegen einer Exception
// einen Zeitgeber (100 ms), der höchstens WatchMs lang die sichtbaren Fenster
// der IDE (Screen.CustomForms) durchsieht: Texte von Beschriftungen und
// Feldern, Beschriftungen der Knöpfe. Ob es der Exception-Dialog ist,
// entscheidet TAtlasDebugExceptionDialog (Kern). Erkannt meldet OnFound
// einmal je Halt mit dem Ergebnis; ContinueFound schließt den Dialog über
// seinen Knopf „Fortsetzen“ (still fortsetzen, Ignorier-Liste).
// Fortsetzen, Ende der Sitzung oder Cancel beenden die Suche.
// Für die Studie aus #783 steht im Protokoll einmal je Sitzung die Klasse des
// erkannten Fensters und seine Knöpfe, nie die Meldung (sie kann Daten des
// Programms enthalten). Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.ExtCtrls,
  Atlas.Core.Debug.ExceptionDialog;

type
  TAtlasDebugDialogFound = reference to procedure(const AScan: TAtlasDebugDialogScan);

  TAtlasIdeExceptionDialog = class
  public const
    /// <summary>So lange wartet Atlas nach dem Halt auf den Dialog.</summary>
    WatchMs = 3000;
    IntervalMs = 100;
  private
    FTimer: TTimer;
    FStartedAt: UInt64;
    FForm: TCustomForm;
    FScan: TAtlasDebugDialogScan;
    FButtons: TArray<TControl>;
    FOnFound: TAtlasDebugDialogFound;
    FOnTimeout: TProc;
    FLogged: Boolean;
    procedure Tick(Sender: TObject);
    function ScanForm(AForm: TCustomForm): Boolean;
    procedure Collect(AControl: TWinControl; var ATexts, AButtons: TArray<string>;
      var AButtonControls: TArray<TControl>);
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Nach einem Halt wegen einer Exception: Dialog suchen. AOnFound kommt höchstens einmal,
    /// AOnTimeout, wenn bis WatchMs keiner erschien.</summary>
    procedure Watch(const AOnFound: TAtlasDebugDialogFound; const AOnTimeout: TProc);
    procedure Cancel;
    /// <summary>Den erkannten Dialog mit „Fortsetzen“ schließen; False, wenn er nicht mehr da ist oder keinen
    /// solchen Knopf hat.</summary>
    function ContinueFound: Boolean;
    /// <summary>Für das Protokoll vergessen, dass der Dialog schon beschrieben ist (neue Sitzung).</summary>
    procedure NewSession;
    function Watching: Boolean;
  end;

implementation

uses
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Atlas.Core.Diagnostics.Guard;

type
  // Zugriff auf die geschützten Caption und Text von TControl.
  TControlAccess = class(TControl);

{ TAtlasIdeExceptionDialog }

constructor TAtlasIdeExceptionDialog.Create;
begin
  inherited Create;
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := IntervalMs;
  FTimer.OnTimer := Tick;
end;

destructor TAtlasIdeExceptionDialog.Destroy;
begin
  Cancel;
  FreeAndNil(FTimer);
  inherited Destroy;
end;

procedure TAtlasIdeExceptionDialog.NewSession;
begin
  FLogged := False;
end;

function TAtlasIdeExceptionDialog.Watching: Boolean;
begin
  Result := FTimer.Enabled;
end;

procedure TAtlasIdeExceptionDialog.Watch(const AOnFound: TAtlasDebugDialogFound; const AOnTimeout: TProc);
begin
  Cancel;
  FOnFound := AOnFound;
  FOnTimeout := AOnTimeout;
  FStartedAt := TThread.GetTickCount64;
  FTimer.Enabled := True;
  // Steht der Dialog schon (er kam vor der Meldung des Halts), sofort.
  Tick(nil);
end;

procedure TAtlasIdeExceptionDialog.Cancel;
begin
  if FTimer <> nil then
    FTimer.Enabled := False;
  FOnFound := nil;
  FOnTimeout := nil;
  FForm := nil;
  FButtons := nil;
  FScan := Default(TAtlasDebugDialogScan);
end;

procedure TAtlasIdeExceptionDialog.Collect(AControl: TWinControl; var ATexts, AButtons: TArray<string>;
  var AButtonControls: TArray<TControl>);
var
  Index: Integer;
  Child: TControl;
  Text: string;
begin
  for Index := 0 to AControl.ControlCount - 1 do
  begin
    Child := AControl.Controls[Index];
    if not Child.Visible then
      Continue;
    if Child is TButtonControl then
    begin
      AButtons := AButtons + [TControlAccess(Child).Caption];
      AButtonControls := AButtonControls + [Child];
    end
    else if (Child is TCustomLabel) or (Child is TCustomStaticText) then
    begin
      Text := TControlAccess(Child).Caption;
      if Text <> '' then
        ATexts := ATexts + [Text];
    end
    else if Child is TCustomEdit then
    begin
      Text := TControlAccess(Child).Text;
      if Text <> '' then
        ATexts := ATexts + [Text];
    end;
    if Child is TWinControl then
      Collect(TWinControl(Child), ATexts, AButtons, AButtonControls);
  end;
end;

function TAtlasIdeExceptionDialog.ScanForm(AForm: TCustomForm): Boolean;
var
  Texts, Buttons: TArray<string>;
  Controls: TArray<TControl>;
  Scan: TAtlasDebugDialogScan;
begin
  Texts := nil;
  Buttons := nil;
  Controls := nil;
  Collect(AForm, Texts, Buttons, Controls);
  Scan := TAtlasDebugExceptionDialog.Recognize(Texts, Buttons);
  Result := Scan.HasException;
  if not Result then
    Exit;
  FForm := AForm;
  FScan := Scan;
  FButtons := Controls;
  if not FLogged then
  begin
    FLogged := True;
    TAtlasGuard.Log(Format('Exception-Dialog der IDE erkannt: %s, Knöpfe: %s, Fortsetzen möglich: %s',
      [AForm.ClassName, string.Join(' | ', Buttons), BoolToStr(Scan.CanContinue, True)]));
  end;
end;

procedure TAtlasIdeExceptionDialog.Tick(Sender: TObject);
var
  Index: Integer;
  Form: TCustomForm;
  Found: TAtlasDebugDialogFound;
  Timeout: TProc;
begin
  if not FTimer.Enabled then
    Exit;
  for Index := 0 to Screen.CustomFormCount - 1 do
  begin
    Form := Screen.CustomForms[Index];
    if not Form.Visible or (Form = Application.MainForm) then
      Continue;
    if ScanForm(Form) then
    begin
      FTimer.Enabled := False;
      Found := FOnFound;
      FOnFound := nil;
      FOnTimeout := nil;
      if Assigned(Found) then
        TAtlasGuard.Run(TAtlasFeature.Debugger,
          procedure
          begin
            Found(FScan);
          end);
      Exit;
    end;
  end;
  if TThread.GetTickCount64 - FStartedAt >= WatchMs then
  begin
    FTimer.Enabled := False;
    Timeout := FOnTimeout;
    FOnFound := nil;
    FOnTimeout := nil;
    if Assigned(Timeout) then
      TAtlasGuard.Run(TAtlasFeature.Debugger, Timeout);
  end;
end;

function TAtlasIdeExceptionDialog.ContinueFound: Boolean;
var
  Index: Integer;
  Form: TCustomForm;
  Alive: Boolean;
begin
  Result := False;
  if (FForm = nil) or not FScan.CanContinue or (FScan.ContinueIndex > High(FButtons)) then
    Exit;
  // Das Fenster kann inzwischen zu sein; nur ein noch angemeldetes, sichtbares zählt.
  Alive := False;
  for Index := 0 to Screen.CustomFormCount - 1 do
  begin
    Form := Screen.CustomForms[Index];
    if Form = FForm then
    begin
      Alive := Form.Visible;
      Break;
    end;
  end;
  if not Alive then
    Exit;
  if FButtons[FScan.ContinueIndex] is TButton then
  begin
    TButton(FButtons[FScan.ContinueIndex]).Click;
    Result := True;
  end;
  FForm := nil;
end;

end.
