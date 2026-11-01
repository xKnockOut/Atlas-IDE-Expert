unit Atlas.IDE.Debug.ExceptionDialog;

// Den Exception-Dialog der IDE beobachten (#517, #783). Die Open Tools API
// meldet beim Halt wegen einer Exception weder Klasse noch Meldung; der Dialog
// der IDE hat beides. Watch startet nach einem Halt wegen einer Exception
// einen Zeitgeber (100 ms), der höchstens WatchMs lang die sichtbaren Fenster
// der IDE (Screen.CustomForms) durchsieht: Texte von Beschriftungen und
// Feldern, Beschriftungen der Knöpfe. Ob es der Exception-Dialog ist,
// entscheidet TAtlasDebugExceptionDialog (Kern). Erkannt meldet OnFound
// einmal je Halt mit dem Ergebnis; ContinueFound schließt den Dialog über
// seinen Knopf „Fortsetzen“ (still fortsetzen, Ignorier-Liste), BreakFound
// über „Anhalten“ (die Exception-Leiste ersetzt ihn, #783).
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
  Vcl.AppEvnts,
  Atlas.Core.Debug.ExceptionDialog;

type
  TAtlasDebugDialogFound = reference to procedure(const AScan: TAtlasDebugDialogScan);
  /// <summary>Darf der erkannte Dialog unsichtbar bleiben (die Exception-Leiste ersetzt ihn)?</summary>
  TAtlasDebugDialogMayHide = reference to function(const AScan: TAtlasDebugDialogScan): Boolean;

  TAtlasIdeExceptionDialog = class
  public const
    /// <summary>So lange wartet Atlas nach dem Halt auf den Dialog.</summary>
    WatchMs = 3000;
    IntervalMs = 100;
    /// <summary>Steht ein ausgeblendeter Dialog so lange noch, wird er wieder sichtbar (die IDE nie verdeckt
    /// blockieren).</summary>
    HiddenSafetyMs = 1500;
  private
    FTimer: TTimer;
    // Beginn eines modalen Fensters (vor Show): den Dialog erkennen, bevor er gezeichnet ist.
    FEvents: TApplicationEvents;
    FSafety: TTimer;
    FHidden: TCustomForm;
    FMayHide: TAtlasDebugDialogMayHide;
    FStartedAt: UInt64;
    FForm: TCustomForm;
    FScan: TAtlasDebugDialogScan;
    FButtons: TArray<TControl>;
    FOnFound: TAtlasDebugDialogFound;
    FOnTimeout: TProc;
    FLogged: Boolean;
    // Bereit, während das Programm läuft: ohne Zeitlimit, nur modale Fenster (Arm).
    FArmed: Boolean;
    procedure ModalBegin(Sender: TObject);
    procedure ModalEnd(Sender: TObject);
    procedure SafetyTick(Sender: TObject);
    procedure Unhide;
    procedure Tick(Sender: TObject);
    function ScanForm(AForm: TCustomForm): Boolean;
    procedure Collect(AControl: TWinControl; var ATexts, AButtons: TArray<string>;
      var AButtonControls: TArray<TControl>);
    /// <summary>Knopf AIndex des erkannten Dialogs drücken, solange er noch sichtbar ist.</summary>
    function ClickFound(AIndex: Integer): Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Nach einem Halt wegen einer Exception: Dialog suchen. AOnFound kommt höchstens einmal,
    /// AOnTimeout, wenn bis WatchMs keiner erschien.</summary>
    procedure Watch(const AOnFound: TAtlasDebugDialogFound; const AOnTimeout: TProc);
    /// <summary>Während das Programm läuft: auf den Dialog warten, ohne Zeitlimit. Die IDE zeigt ihn in ihrer
    /// Behandlung des Halts, bevor Atlas den Halt gemeldet bekommt; nur so lässt er sich ersetzen (#783).
    /// </summary>
    procedure Arm(const AOnFound: TAtlasDebugDialogFound);
    function Armed: Boolean;
    procedure Cancel;
    /// <summary>Den erkannten Dialog mit „Fortsetzen“ schließen; False, wenn er nicht mehr da ist oder keinen
    /// solchen Knopf hat.</summary>
    function ContinueFound: Boolean;
    /// <summary>Den erkannten Dialog mit „Anhalten“ schließen; der Prozess bleibt stehen (#783).</summary>
    function BreakFound: Boolean;
    /// <summary>Für das Protokoll vergessen, dass der Dialog schon beschrieben ist (neue Sitzung).</summary>
    procedure NewSession;
    function Watching: Boolean;
    /// <summary>Ohne Rückruf bleibt der Dialog immer sichtbar.</summary>
    property MayHide: TAtlasDebugDialogMayHide read FMayHide write FMayHide;
  end;

implementation

uses
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Atlas.Core.Diagnostics.Guard;

type
  // Zugriff auf die geschützten Caption und Text von TControl.
  TControlAccess = class(TControl);
  // Zugriff auf die geschützten AlphaBlend und AlphaBlendValue von TCustomForm.
  TFormAccess = class(TCustomForm);

{ TAtlasIdeExceptionDialog }

constructor TAtlasIdeExceptionDialog.Create;
begin
  inherited Create;
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := IntervalMs;
  FTimer.OnTimer := Tick;
  FSafety := TTimer.Create(nil);
  FSafety.Enabled := False;
  FSafety.Interval := HiddenSafetyMs;
  FSafety.OnTimer := SafetyTick;
  FEvents := TApplicationEvents.Create(nil);
  FEvents.OnModalBegin := ModalBegin;
  FEvents.OnModalEnd := ModalEnd;
end;

procedure TAtlasIdeExceptionDialog.ModalBegin(Sender: TObject);
var
  Index: Integer;
  Form: TCustomForm;
begin
  // Nur, solange Atlas auf den Dialog wartet; ShowModal hat das Fenster noch nicht gezeigt.
  if not FArmed or (FHidden <> nil) or not Assigned(FMayHide) then
    Exit;
  try
    for Index := 0 to Screen.CustomFormCount - 1 do
    begin
      Form := Screen.CustomForms[Index];
      if Form.Visible or (Form = Application.MainForm) or (fsModal in Form.FormState) then
        Continue;
      if ScanForm(Form) then
      begin
        if FMayHide(FScan) then
        begin
          // Vor dem ersten Zeichnen durchsichtig; der Takt drückt gleich „Anhalten“ bzw. „Fortsetzen“.
          TFormAccess(Form).AlphaBlendValue := 0;
          TFormAccess(Form).AlphaBlend := True;
          FHidden := Form;
          FSafety.Enabled := True;
        end;
        Exit;
      end;
    end;
  except
    // Ein Fehler hier darf die IDE nicht stören: der Dialog bleibt dann einfach sichtbar.
    on E: Exception do
      TAtlasGuard.Log('Exception-Dialog ausblenden: ' + E.ClassName + ': ' + E.Message);
  end;
end;

procedure TAtlasIdeExceptionDialog.ModalEnd(Sender: TObject);
begin
  // Nach Hide: unsichtbar zurückstellen, falls die IDE das Formular wiederverwendet.
  Unhide;
end;

procedure TAtlasIdeExceptionDialog.SafetyTick(Sender: TObject);
begin
  // Der Dialog steht noch (nichts hat ihn geschlossen): wieder zeigen, damit die IDE bedienbar bleibt.
  if FHidden <> nil then
    TAtlasGuard.Log('Exception-Dialog: nach dem Ausblenden nicht geschlossen; wieder sichtbar');
  Unhide;
end;

procedure TAtlasIdeExceptionDialog.Unhide;
var
  Index: Integer;
begin
  FSafety.Enabled := False;
  if FHidden = nil then
    Exit;
  // Nur ein noch angemeldetes Formular anfassen.
  for Index := 0 to Screen.CustomFormCount - 1 do
    if Screen.CustomForms[Index] = FHidden then
    begin
      TFormAccess(FHidden).AlphaBlend := False;
      TFormAccess(FHidden).AlphaBlendValue := 255;
      Break;
    end;
  FHidden := nil;
end;

destructor TAtlasIdeExceptionDialog.Destroy;
begin
  Cancel;
  if FSafety <> nil then
    Unhide;
  FreeAndNil(FEvents);
  FreeAndNil(FSafety);
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

procedure TAtlasIdeExceptionDialog.Arm(const AOnFound: TAtlasDebugDialogFound);
begin
  Cancel;
  FOnFound := AOnFound;
  FArmed := True;
  FTimer.Enabled := True;
end;

function TAtlasIdeExceptionDialog.Armed: Boolean;
begin
  Result := FArmed and FTimer.Enabled;
end;

procedure TAtlasIdeExceptionDialog.Cancel;
begin
  FArmed := False;
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
    // Bereit (Programm läuft): nur modale Fenster, damit der Takt die IDE nicht durchsucht.
    if FArmed and not (fsModal in Form.FormState) then
      Continue;
    if ScanForm(Form) then
    begin
      FTimer.Enabled := False;
      FArmed := False;
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
  if not FArmed and (TThread.GetTickCount64 - FStartedAt >= WatchMs) then
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
begin
  Result := FScan.CanContinue and ClickFound(FScan.ContinueIndex);
end;

function TAtlasIdeExceptionDialog.BreakFound: Boolean;
begin
  Result := FScan.CanContinue and ClickFound(FScan.BreakIndex);
end;

function TAtlasIdeExceptionDialog.ClickFound(AIndex: Integer): Boolean;
var
  Index: Integer;
  Form: TCustomForm;
  Alive: Boolean;
begin
  Result := False;
  if (FForm = nil) or (AIndex < 0) or (AIndex > High(FButtons)) then
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
  if FButtons[AIndex] is TButton then
  begin
    TButton(FButtons[AIndex]).Click;
    Result := True;
  end;
  FForm := nil;
end;

end.
