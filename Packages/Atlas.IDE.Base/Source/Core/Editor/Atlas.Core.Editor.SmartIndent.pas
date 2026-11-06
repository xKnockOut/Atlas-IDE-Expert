unit Atlas.Core.Editor.SmartIndent;

// Einrückung beim Tippen (#1827), Plugin-Kern ohne VCL und Open Tools API:
// Argumente für atlas.server.smartIndent bauen, die Antwort lesen und
// entscheiden, ob sie noch passt.
// - Nach Enter fragt die IDE-Schicht im Hintergrund; kommt die Antwort, gilt sie
//   nur, wenn Datei, Zeile und Text der neuen Zeile und der Zeile darüber
//   unverändert sind und die Schreibmarke noch in dieser Zeile vor dem Text
//   steht (schnelles Tippen verwirft sie).
// - Eine Zeile "/befehl" über der neuen Zeile gehört den Schnellbefehlen (#293);
//   dann fragt Atlas nicht.
// - Einfügen (#1832): nur die Spalte einer Anweisung am Anfang einer Zeile.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Lsp.TextChanges,
  Atlas.Core.Lsp.WorkspaceEdits;

type
  /// <summary>Stand, für den gefragt wurde.</summary>
  TAtlasSmartIndentAsked = record
    FileName: string;
    /// <summary>Neue Zeile, 0-basiert.</summary>
    Line: Integer;
    /// <summary>Text der neuen Zeile und der Zeile darüber.</summary>
    LineText: string;
    PreviousText: string;
    class function Create(const AFileName: string; ALine: Integer; const ALineText, APreviousText: string):
      TAtlasSmartIndentAsked; static;
  end;

  TAtlasSmartIndentAnswer = record
    Edits: TArray<TLspTextEdit>;
    Cursor: TLspTextPosition;
  end;

  TAtlasSmartIndent = class
  public const
    Command = 'atlas.server.smartIndent';
    /// <summary>Beim Tippen: lieber nichts tun als spät noch einrücken.</summary>
    TimeoutMs = 1500;
  public
    /// <summary>Soll Atlas nach Enter fragen? Nicht unter einer Zeile "/befehl" (Schnellbefehl, #293).</summary>
    class function Applies(const APreviousText: string): Boolean; static;
    /// <summary>Pascal-Quelltext (.pas, .dpr, .dpk, .inc)? Nur dort fragt Atlas.</summary>
    class function IsSource(const AFileName: string): Boolean; static;
    /// <summary>Argumente als JSON-Text: URI, Zeile, Editor-Optionen; AColumnOnly für das Einfügen.</summary>
    class function Arguments(const AUri: string; ALine, ATabSize: Integer; AInsertSpaces, AColumnOnly: Boolean):
      string; static;
    /// <summary>Antwort nach Enter; False bei null oder ungültiger Antwort.</summary>
    class function ReadAnswer(const AValue: TJSONValue; out AAnswer: TAtlasSmartIndentAnswer): Boolean; static;
    /// <summary>Antwort im Spaltenmodus; False bei null.</summary>
    class function ReadColumn(const AValue: TJSONValue; out AColumn: Integer): Boolean; static;
    /// <summary>Gilt die Antwort für AAsked noch? ANow: Stand jetzt; ACursorCharacter: Schreibmarke in der neuen
    /// Zeile (0-basiert), ACursorLine ihre Zeile.</summary>
    class function StillValid(const AAsked, ANow: TAtlasSmartIndentAsked; ACursorLine, ACursorCharacter: Integer):
      Boolean; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Core.Editor.SlashTrigger;

{ TAtlasSmartIndentAsked }

class function TAtlasSmartIndentAsked.Create(const AFileName: string; ALine: Integer;
  const ALineText, APreviousText: string): TAtlasSmartIndentAsked;
begin
  Result.FileName := AFileName;
  Result.Line := ALine;
  Result.LineText := ALineText;
  Result.PreviousText := APreviousText;
end;

{ TAtlasSmartIndent }

class function TAtlasSmartIndent.Applies(const APreviousText: string): Boolean;
begin
  Result := TAtlasSlashTrigger.Detect(APreviousText, '') <> TAtlasSlashKind.Command;
end;

class function TAtlasSmartIndent.IsSource(const AFileName: string): Boolean;
begin
  Result := MatchText(ExtractFileExt(AFileName), ['.pas', '.dpr', '.dpk', '.inc']);
end;

class function TAtlasSmartIndent.Arguments(const AUri: string; ALine, ATabSize: Integer;
  AInsertSpaces, AColumnOnly: Boolean): string;
var
  mValues: TJSONArray;
  mOptions: TJSONObject;
begin
  mValues := TJSONArray.Create;
  try
    mValues.Add(AUri);
    mValues.Add(ALine);
    mOptions := TJSONObject.Create;
    mOptions.AddPair('tabSize', TJSONNumber.Create(ATabSize));
    mOptions.AddPair('insertSpaces', TJSONBool.Create(AInsertSpaces));
    mValues.AddElement(mOptions);
    if AColumnOnly then
    begin
      mValues.Add('column');
    end;
    Result := mValues.ToJSON([]);
  finally
    mValues.Free;
  end;
end;

/// <summary>Position aus {line, character}.</summary>
function ReadPosition(const AValue: TJSONValue; out APosition: TLspTextPosition): Boolean;
begin
  APosition := Default(TLspTextPosition);
  Result := (AValue is TJSONObject) and AValue.TryGetValue<Integer>('line', APosition.Line) and
    AValue.TryGetValue<Integer>('character', APosition.Character);
end;

class function TAtlasSmartIndent.ReadAnswer(const AValue: TJSONValue; out AAnswer: TAtlasSmartIndentAnswer): Boolean;
var
  mEdits: TJSONArray;
  mItem: TJSONValue;
  mEdit: TLspTextEdit;
begin
  AAnswer := Default(TAtlasSmartIndentAnswer);
  Result := (AValue is TJSONObject) and ReadPosition(TJSONObject(AValue).GetValue('cursor'), AAnswer.Cursor) and
    TJSONObject(AValue).TryGetValue<TJSONArray>('edits', mEdits);
  if not Result then
  begin
    Exit;
  end;
  for mItem in mEdits do
  begin
    if not TLspTextEdit.FromJson(mItem, mEdit) then
    begin
      Exit(False);
    end;
    AAnswer.Edits := AAnswer.Edits + [mEdit];
  end;
end;

class function TAtlasSmartIndent.ReadColumn(const AValue: TJSONValue; out AColumn: Integer): Boolean;
begin
  AColumn := 0;
  Result := (AValue is TJSONObject) and AValue.TryGetValue<Integer>('column', AColumn) and (AColumn >= 0);
end;

class function TAtlasSmartIndent.StillValid(const AAsked, ANow: TAtlasSmartIndentAsked;
  ACursorLine, ACursorCharacter: Integer): Boolean;
begin
  Result := SameText(AAsked.FileName, ANow.FileName) and (AAsked.Line = ANow.Line) and
    (AAsked.LineText = ANow.LineText) and (AAsked.PreviousText = ANow.PreviousText) and (ACursorLine = AAsked.Line);
  // Vor der Schreibmarke darf nur Leerraum stehen (sie steht noch am Anfang der Zeile).
  Result := Result and (Trim(Copy(ANow.LineText, 1, ACursorCharacter)) = '');
end;

end.
