unit Atlas.IDE.Debug.NextStatement;

// Nächste Anweisung setzen (#871) in der IDE, ohne Oberfläche (die Spalte mit dem ziehbaren Pfeil liegt in
// Atlas.IDE.Debug.NextStatementColumn):
// - Prüfen: TAtlasNextStatement auf dem Text der Datei des Ausführungspunkts; Folge bzw. Grund als Text.
// - Setzen: Die IDE beantwortet nur „welche Zeile hat diese Adresse“ (IOTAProcess.SourceLocationFromAddress);
//   TAtlasNextStatement.FindAddress sucht damit vom Befehlszähler aus die Adresse der Zielzeile. Der
//   Befehlszähler wird im Thread-Kontext der IDE geschrieben (IOTAThread.OTAThreadContextEx, win32.Eip bzw.
//   win64.Rip) und zur Kontrolle wieder gelesen. Andere Plattformen lehnt Atlas ab.
// - Beim ersten Setzen ein Hinweis auf die Folgen (experimentell); bestätigt wird er gemerkt.
// - Bis zum nächsten Halt gilt die gesetzte Zeile als Ausführungspunkt (die IDE zeichnet ihren Pfeil erst beim
//   nächsten Schritt neu).
// Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  ToolsAPI,
  Atlas.Core.Debug.NextStatement,
  Atlas.Core.Notifications.MessageSink;

type
  TAtlasIdeNextStatement = class
  private class var
    FMessage: TAtlasMessageSink;
    FStarted: Boolean;
    FCheck: TAtlasNextStatement;
    FCheckText: string;
    FMovedFile: string;
    FMovedLine: Integer;
    FMovedStop: Integer;
    /// <summary>Prüfung für AText, nur bei geändertem Text neu gelesen.</summary>
    class function CheckFor(const AText: string): TAtlasNextStatement; static;
    class function TargetLine(out AFileName: string; out ALine: Integer): Boolean; static;
    class function Confirmed: Boolean; static;
    class function ReadAddress(const AThread: IOTAThread; out AAddress: UInt64): Boolean; static;
    class function WriteAddress(const AThread: IOTAThread; AAddress: UInt64): Boolean; static;
    class function Supported: Boolean; static;
    class function EffectText(AFrom, ATo: Integer): string; static;
    /// <summary>Angehalten, Ziel erlaubt, Plattform passt, Hinweis bestätigt? AText: Folge; sonst Meldung.</summary>
    class function Prepare(const AFileName: string; ALine: Integer; out AThread: IOTAThread;
      out AText: string): Boolean; static;
    /// <summary>Adresse der Zielzeile über die IDE; sonst Meldung.</summary>
    class function Locate(const AThread: IOTAThread; const AFileName: string; ALine: Integer;
      out AAddress: UInt64): Boolean; static;
  public
    /// <summary>Teil starten; AMessage schreibt eine Zeile in die Meldungsansicht.</summary>
    class procedure Start(const AMessage: TProc<string>); static;
    class procedure Release; static;
    class function Started: Boolean; static;
    /// <summary>debug.dragNextStatement an (und Atlas an) und Teil gestartet?</summary>
    class function Enabled: Boolean; static;
    /// <summary>Ausführungspunkt (Zeile ab 0): nach eigenem Setzen die gesetzte Zeile bis zum nächsten Halt,
    /// sonst die des angehaltenen Threads. False, wenn das Programm nicht angehalten ist.</summary>
    class function Current(out AFileName: string; out ALine: Integer): Boolean; static;
    /// <summary>Darf die nächste Anweisung auf ALine (ab 0) von AFileName? AText: Folge („Zeilen 117–119 laufen
    /// erneut“) bzw. Grund der Sperre.</summary>
    class function Preview(const AFileName: string; ALine: Integer; out AText: string): Boolean; static;
    /// <summary>Nächste Anweisung auf ALine (ab 0) von AFileName setzen; False mit Meldung.</summary>
    class function MoveTo(const AFileName: string; ALine: Integer): Boolean; static;
    /// <summary>Befehl Atlas.DebugSetNextStatement: Zeile des letzten Rechtsklicks in den Rand, sonst die Zeile der
    /// Schreibmarke.</summary>
    class procedure SetHere; static;
  end;

implementation

uses
  Vcl.Dialogs,
  System.UITypes,
  Atlas.Core.Settings.Plugin,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.GutterMarks,
  Atlas.IDE.Debug.Session,
  Atlas.IDE.Debug.Breakpoints,
  Atlas.UI.Debug.NextStatement.Strings;

const
  cWin32 = 'Win32';
  cWin64 = 'Win64';

{ TAtlasIdeNextStatement }

class procedure TAtlasIdeNextStatement.Start(const AMessage: TProc<string>);
begin
  FMessage := TAtlasMessageSink.Create(AMessage);
  FMovedStop := -1;
  FStarted := True;
  TAtlasIdeDebugSession.Start;
end;

class procedure TAtlasIdeNextStatement.Release;
begin
  FStarted := False;
  FMessage.Clear;
  FreeAndNil(FCheck);
  FCheckText := '';
  FMovedFile := '';
  FMovedStop := -1;
end;

class function TAtlasIdeNextStatement.Started: Boolean;
begin
  Result := FStarted;
end;

class function TAtlasIdeNextStatement.Enabled: Boolean;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := FStarted and mSettings.Enabled and mSettings.DebugDragNextStatement;
end;

class function TAtlasIdeNextStatement.CheckFor(const AText: string): TAtlasNextStatement;
begin
  if (FCheck = nil) or (AText <> FCheckText) then
  begin
    FreeAndNil(FCheck);
    FCheck := TAtlasNextStatement.Create(AText);
    FCheckText := AText;
  end;
  Result := FCheck;
end;

class function TAtlasIdeNextStatement.Current(out AFileName: string; out ALine: Integer): Boolean;
var
  mProcess: IOTAProcess;
begin
  AFileName := '';
  ALine := -1;
  mProcess := TAtlasIdeBreakpoints.StoppedProcess;
  if mProcess = nil then
  begin
    Exit(False);
  end;
  if (FMovedFile <> '') and (FMovedStop = TAtlasIdeDebugSession.StopCount) then
  begin
    AFileName := FMovedFile;
    ALine := FMovedLine;
    Exit(True);
  end;
  Result := TAtlasIdeBreakpoints.Position(mProcess.CurrentThread, AFileName, ALine);
end;

class function TAtlasIdeNextStatement.EffectText(AFrom, ATo: Integer): string;
var
  mFirst, mLast: Integer;
  mEffect: TAtlasNextStatementEffect;
  mId: TAtlasNextStatementTextId;
begin
  mEffect := TAtlasNextStatement.Effect(AFrom, ATo, mFirst, mLast);
  if mEffect = TAtlasNextStatementEffect.None then
  begin
    Exit(TAtlasNextStatementStrings.Text(TAtlasNextStatementTextId.SameLine));
  end;
  if mEffect = TAtlasNextStatementEffect.Rerun then
  begin
    mId := TAtlasNextStatementTextId.RerunMany;
    if mFirst = mLast then
    begin
      mId := TAtlasNextStatementTextId.RerunOne;
    end;
  end
  else
  begin
    mId := TAtlasNextStatementTextId.SkipMany;
    if mFirst = mLast then
    begin
      mId := TAtlasNextStatementTextId.SkipOne;
    end;
  end;
  // Eine Zeile: der zweite Wert bleibt ungenutzt.
  Result := TAtlasNextStatementStrings.Fmt(mId, [mFirst + 1, mLast + 1]);
end;

/// <summary>Grund der Sperre als Text.</summary>
function VerdictText(AVerdict: TAtlasNextStatementVerdict): string;
const
  cIds: array[TAtlasNextStatementVerdict] of TAtlasNextStatementTextId = (TAtlasNextStatementTextId.TipTitle,
    TAtlasNextStatementTextId.SameLine, TAtlasNextStatementTextId.OutsideRoutine, TAtlasNextStatementTextId.NoCode,
    TAtlasNextStatementTextId.OtherBlock, TAtlasNextStatementTextId.ForHead);
begin
  Result := TAtlasNextStatementStrings.Text(cIds[AVerdict]);
end;

class function TAtlasIdeNextStatement.Preview(const AFileName: string; ALine: Integer; out AText: string): Boolean;
var
  mFileName, mSource: string;
  mFrom: Integer;
  mVerdict: TAtlasNextStatementVerdict;
begin
  Result := False;
  if not Current(mFileName, mFrom) then
  begin
    AText := TAtlasNextStatementStrings.Text(TAtlasNextStatementTextId.NotStopped);
    Exit;
  end;
  if not SameText(mFileName, AFileName) or not TAtlasIdeFiles.SourceText(AFileName, mSource) then
  begin
    AText := VerdictText(TAtlasNextStatementVerdict.OutsideRoutine);
    Exit;
  end;
  mVerdict := CheckFor(mSource).Check(mFrom, ALine);
  Result := mVerdict = TAtlasNextStatementVerdict.Allowed;
  if Result then
  begin
    AText := EffectText(mFrom, ALine);
  end
  else
  begin
    AText := VerdictText(mVerdict);
  end;
end;

class function TAtlasIdeNextStatement.Supported: Boolean;
var
  mPlatform: string;
begin
  mPlatform := TAtlasIdeDebugSession.LaunchPlatform;
  Result := SameText(mPlatform, cWin32) or SameText(mPlatform, cWin64);
  if not Result then
  begin
    FMessage.Say(TAtlasNextStatementStrings.Fmt(TAtlasNextStatementTextId.Platform, [mPlatform]));
  end;
end;

class function TAtlasIdeNextStatement.ReadAddress(const AThread: IOTAThread; out AAddress: UInt64): Boolean;
var
  mContext: TOTAThreadContextEx;
begin
  AAddress := 0;
  mContext := AThread.GetOTAThreadContextEx;
  if SameText(TAtlasIdeDebugSession.LaunchPlatform, cWin64) then
  begin
    AAddress := mContext.win64.Rip;
  end
  else
  begin
    AAddress := mContext.win32.Eip;
  end;
  Result := AAddress <> 0;
end;

class function TAtlasIdeNextStatement.WriteAddress(const AThread: IOTAThread; AAddress: UInt64): Boolean;
var
  mContext: TOTAThreadContextEx;
  mCheck: UInt64;
begin
  mContext := AThread.GetOTAThreadContextEx;
  if SameText(TAtlasIdeDebugSession.LaunchPlatform, cWin64) then
  begin
    mContext.win64.Rip := AAddress;
  end
  else
  begin
    mContext.win32.Eip := Cardinal(AAddress);
  end;
  AThread.SetOTAThreadContextEx(mContext);
  // Nur wenn der Debugger den Wert übernommen hat.
  Result := ReadAddress(AThread, mCheck) and (mCheck = AAddress);
end;

class function TAtlasIdeNextStatement.Confirmed: Boolean;
var
  mSettings: TAtlasPluginSettings;
begin
  if TAtlasIdeSettings.Current.DebugNextStatementNoticeShown then
  begin
    Exit(True);
  end;
  Result := MessageDlg(TAtlasNextStatementStrings.Text(TAtlasNextStatementTextId.NoticeConfirm), mtWarning,
    [mbYes, mbNo], 0) = mrYes;
  if Result then
  begin
    mSettings := TAtlasIdeSettings.Stored;
    mSettings.DebugNextStatementNoticeShown := True;
    TAtlasIdeSettings.Update(mSettings);
  end;
end;

/// <summary>Zeile (ab 0) zu einer Adresse über die IDE; Dateien gelten als gleich, wenn der Name gleich ist
/// (die IDE nennt sie je nach Debug-Information mit oder ohne Pfad).</summary>
function LineLookup(const AProcess: IOTAProcess; const AFileName: string): TAtlasLineAtAddress;
begin
  Result :=
    function(AAddress: UInt64; out AName: string; out ALine: Integer): Boolean
    var
      mLine: Integer;
    begin
      AName := '';
      mLine := 0;
      AProcess.SourceLocationFromAddress(TOTAAddress(AAddress), AName, mLine);
      if SameText(ExtractFileName(AName), ExtractFileName(AFileName)) then
      begin
        AName := AFileName;
      end;
      ALine := mLine - 1;
      Result := (AName <> '') and (mLine > 0);
    end;
end;

class function TAtlasIdeNextStatement.Prepare(const AFileName: string; ALine: Integer; out AThread: IOTAThread;
  out AText: string): Boolean;
var
  mFileName: string;
  mFrom: Integer;
begin
  AThread := nil;
  AText := '';
  if not Current(mFileName, mFrom) then
  begin
    FMessage.Say(TAtlasNextStatementStrings.Text(TAtlasNextStatementTextId.NotStopped));
    Exit(False);
  end;
  if not Preview(AFileName, ALine, AText) then
  begin
    FMessage.Say(TAtlasNextStatementStrings.Text(TAtlasNextStatementTextId.TipTitle) + ': ' + AText);
    Exit(False);
  end;
  AThread := TAtlasIdeBreakpoints.StoppedProcess.CurrentThread;
  Result := (AThread <> nil) and Supported and Confirmed;
end;

class function TAtlasIdeNextStatement.Locate(const AThread: IOTAThread; const AFileName: string; ALine: Integer;
  out AAddress: UInt64): Boolean;
var
  mTarget: TAtlasNextStatementTarget;
  mCurrent: UInt64;
begin
  AAddress := 0;
  mTarget := Default(TAtlasNextStatementTarget);
  mTarget.FileName := AFileName;
  mTarget.Line := ALine;
  Result := ReadAddress(AThread, mCurrent) and FCheck.RoutineAt(ALine, mTarget.FirstLine, mTarget.LastLine) and
    TAtlasNextStatement.FindAddress(mCurrent, mTarget, LineLookup(TAtlasIdeBreakpoints.StoppedProcess, AFileName),
    AAddress);
  if not Result then
  begin
    FMessage.Say(TAtlasNextStatementStrings.Fmt(TAtlasNextStatementTextId.NoAddress, [ALine + 1]));
  end;
end;

class function TAtlasIdeNextStatement.MoveTo(const AFileName: string; ALine: Integer): Boolean;
var
  mThread: IOTAThread;
  mText: string;
  mAddress: UInt64;
begin
  Result := Prepare(AFileName, ALine, mThread, mText) and Locate(mThread, AFileName, ALine, mAddress);
  if not Result then
  begin
    Exit;
  end;
  Result := WriteAddress(mThread, mAddress);
  if not Result then
  begin
    FMessage.Say(TAtlasNextStatementStrings.Text(TAtlasNextStatementTextId.Failed));
    Exit;
  end;
  FMovedFile := AFileName;
  FMovedLine := ALine;
  FMovedStop := TAtlasIdeDebugSession.StopCount;
  FMessage.Say(TAtlasNextStatementStrings.Fmt(TAtlasNextStatementTextId.Moved, [ALine + 1, mText]));
end;

class function TAtlasIdeNextStatement.TargetLine(out AFileName: string; out ALine: Integer): Boolean;
var
  mView: IOTAEditView;
begin
  AFileName := '';
  ALine := -1;
  mView := TAtlasEditorBuffer.ActiveView;
  Result := (mView <> nil) and (mView.Buffer <> nil);
  if not Result then
  begin
    FMessage.Say(TAtlasNextStatementStrings.Text(TAtlasNextStatementTextId.NoEditor));
    Exit;
  end;
  AFileName := mView.Buffer.FileName;
  if not TAtlasIdeGutterMarks.TakeLine(AFileName, ALine) then
  begin
    ALine := mView.CursorPos.Line - 1;
  end;
end;

class procedure TAtlasIdeNextStatement.SetHere;
var
  mFileName: string;
  mLine: Integer;
begin
  if TargetLine(mFileName, mLine) then
  begin
    MoveTo(mFileName, mLine);
  end;
end;

end.
