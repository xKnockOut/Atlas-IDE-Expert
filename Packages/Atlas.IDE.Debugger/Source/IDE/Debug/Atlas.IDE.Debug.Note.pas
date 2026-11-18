unit Atlas.IDE.Debug.Note;

// „Debug-Zustand festhalten“ (#582, debug.note): Im angehaltenen Programm
// hält der Befehl Atlas.DebugNote den Zustand als Markdown-Notiz fest
// (TAtlasDebugNote): Projekt, Ort mit Ausschnitt, Aufrufstapel mit eigenem
// Code, lokale Variablen und überwachte Ausdrücke (TAtlasIdeDebugNoteValues
// wertet sie aus, auch ohne offenes Fenster „Variablen“), letzte Exception
// und die letzten Zeilen des Ereignisprotokolls. Werte geheimer Namen
// erscheinen als ***.
// Die Notiz kommt in die Zwischenablage, mit debug.note.saveFile auch als
// Datei in den Ordner „debug-notizen“ neben dem Projekt
// (TAtlasDataFile.Write: UTF-8 ohne BOM, Ordner wird angelegt).
// Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  Atlas.Core.Debug.Note,
  Atlas.IDE.Debug.Variables,
  Atlas.IDE.Debug.NoteValues;

type
  /// <summary>Dienste von Base (gesetzt von der Komposition).</summary>
  TAtlasDebugNoteServices = record
    Message: TProc<string>;
    Session: TAtlasVariablesSessionFunc;
    Run: TAtlasVariablesRunner;
  end;

  TAtlasIdeDebugNote = class
  private class var
    FServices: TAtlasDebugNoteServices;
    FValues: TAtlasIdeDebugNoteValues;
    class procedure Say(const AText: string); static;
    class procedure Deliver(const AData: TAtlasDebugNoteData); static;
  public
    class procedure Start(const AServices: TAtlasDebugNoteServices); static;
    class procedure Release; static;
    class function Started: Boolean; static;
    /// <summary>Befehl Atlas.DebugNote: Notiz des aktuellen Halts.</summary>
    class procedure Execute; static;
    /// <summary>Ordner der Notizen neben dem Projekt AProject und Datei zur Zeit ATime.</summary>
    class function FileOf(const AProject: string; ATime: TDateTime): string; static;
  end;

implementation

uses
  System.IOUtils,
  Vcl.Clipbrd,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Files.DataFile,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Debug.Report,
  Atlas.UI.Debug.Note.Strings;

/// <summary>Sind die Werte da, geht die Notiz mit ihnen hinaus.</summary>
function Collected(const AData: TAtlasDebugNoteData): TAtlasNoteValuesDone;
var
  mData: TAtlasDebugNoteData;
begin
  mData := AData;
  Result :=
    procedure(const ALocals, AWatches: TAtlasDebugNoteValues)
    begin
      mData.Locals := ALocals;
      mData.Watches := AWatches;
      TAtlasIdeDebugNote.Deliver(mData);
    end;
end;

{ TAtlasIdeDebugNote }

class procedure TAtlasIdeDebugNote.Start(const AServices: TAtlasDebugNoteServices);
begin
  FServices := AServices;
  if FValues = nil then
  begin
    FValues := TAtlasIdeDebugNoteValues.Create(AServices.Session, AServices.Run);
  end;
end;

class procedure TAtlasIdeDebugNote.Release;
begin
  // Eine laufende Sammlung endet ohne Rückruf.
  FreeAndNil(FValues);
  FServices := Default(TAtlasDebugNoteServices);
end;

class function TAtlasIdeDebugNote.Started: Boolean;
begin
  Result := FValues <> nil;
end;

class procedure TAtlasIdeDebugNote.Say(const AText: string);
begin
  if Assigned(FServices.Message) then
  begin
    FServices.Message(AText);
  end;
end;

class procedure TAtlasIdeDebugNote.Execute;
var
  mData: TAtlasDebugNoteData;
begin
  if FValues = nil then
  begin
    Exit;
  end;
  if FValues.Busy then
  begin
    Say(TAtlasNoteStrings.Text(TAtlasNoteTextId.NoteBusy));
    Exit;
  end;
  if not TAtlasIdeDebugReport.NoteData(mData) then
  begin
    Say(TAtlasNoteStrings.Text(TAtlasNoteTextId.NoteNotStopped));
    Exit;
  end;
  FValues.Collect(mData.FileName, mData.Line, Collected(mData));
end;

class function TAtlasIdeDebugNote.FileOf(const AProject: string; ATime: TDateTime): string;
begin
  Result := TPath.Combine(TPath.Combine(ExtractFileDir(AProject), TAtlasNoteStrings.Text(TAtlasNoteTextId.NoteFolder)),
    TAtlasIdeDebugReport.NoteFileName(ATime));
end;

class procedure TAtlasIdeDebugNote.Deliver(const AData: TAtlasDebugNoteData);
var
  mData: TAtlasDebugNoteData;
begin
  mData := AData;
  // Der Rückruf kommt aus dem Takt oder der Antwort des Servers: abgesichert wie ein Befehl.
  TAtlasGuard.Run(TAtlasFeature.Debugger,
    procedure
    var
      mMarkdown, mFile: string;
    begin
      mMarkdown := TAtlasDebugNote.Markdown(mData, TAtlasIdeDebugReport.NoteTexts);
      Clipboard.AsText := mMarkdown;
      if not TAtlasIdeSettings.Current.DebugNoteSaveFile or (mData.Project = '') then
      begin
        Say(TAtlasNoteStrings.Text(TAtlasNoteTextId.NoteCopied));
        Exit;
      end;
      mFile := FileOf(mData.Project, mData.Time);
      try
        TAtlasDataFile.Write(mFile, mMarkdown);
        Say(TAtlasNoteStrings.Fmt(TAtlasNoteTextId.NoteSaved, [mFile]));
      except
        on E: Exception do
          Say(TAtlasNoteStrings.Fmt(TAtlasNoteTextId.NoteSaveFailed, [mFile, E.Message]));
      end;
    end);
end;

end.
