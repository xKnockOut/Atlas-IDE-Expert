unit Atlas.Core.Build.Messages;

// Compilermeldungen der IDE (#528), ohne Open Tools API: Modell, Zerlegung
// von "E2003 Undeklarierter Bezeichner …" in Code und Text, Schweregrad aus
// der Art der IDE (msgError, msgWarning …) bzw. ersatzweise aus dem Code, und
// die Parameter der Benachrichtigung atlas/compilerMessages an den Server.
// Der Code ist der Schlüssel, nicht der (deutsche oder englische) Text.
// Die IDE nennt Dateien teils ohne Pfad ("Gallery.Main.pas"); Resolve macht
// daraus volle Pfade, damit der Server die Meldung der Datei zuordnet (#398).

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  System.JSON;

type
  TAtlasCompilerSeverity = (Info, Hint, Warning, Error, Fatal);

  TAtlasCompilerMessage = record
    FileName: string;
    /// <summary>1-basiert wie in der IDE; 0 ohne.</summary>
    Line: Integer;
    Column: Integer;
    Severity: TAtlasCompilerSeverity;
    Code: string;
    Text: string;
  end;

  TAtlasCompilerMessages = class
  public
    /// <summary>Meldung aus den Feldern einer Zeile des Meldungsfensters.</summary>
    class function FromIde(const AKind, AMessage, AFileName: string; ALine, AColumn: Integer): TAtlasCompilerMessage;
      static;
    class function SeverityText(ASeverity: TAtlasCompilerSeverity): string; static;
    /// <summary>Relative Dateinamen zu vollen Pfaden: zuerst eine bekannte Datei (offen oder im Projekt),
    /// deren Pfad auf den Namen endet, sonst der Projektordner, wenn die Datei dort liegt.</summary>
    class function Resolve(const AMessages: TArray<TAtlasCompilerMessage>; const AProjectFile: string;
      const AKnownFiles: TArray<string>): TArray<TAtlasCompilerMessage>; static;
    /// <summary>Parameter für atlas/compilerMessages; Info-Meldungen bleiben weg.</summary>
    class function ToJson(const AMessages: TArray<TAtlasCompilerMessage>; const AProject, APlatform: string;
      ASucceeded, ABackground: Boolean): TJSONObject; overload; static;
    /// <summary>Wie oben mit ABackground = False.</summary>
    class function ToJson(const AMessages: TArray<TAtlasCompilerMessage>; const AProject, APlatform: string;
      ASucceeded: Boolean): TJSONObject; overload; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.StrUtils,
  System.RegularExpressions;

class function TAtlasCompilerMessages.FromIde(const AKind, AMessage, AFileName: string; ALine,
  AColumn: Integer): TAtlasCompilerMessage;
var
  mMatch: TMatch;
  mKind: string;
begin
  Result := Default(TAtlasCompilerMessage);
  Result.FileName := AFileName;
  Result.Line := ALine;
  Result.Column := AColumn;
  Result.Text := Trim(AMessage);
  mMatch := TRegEx.Match(Result.Text, '^([EWHFC]\d{4})\s*:?\s*(.*)$', [roSingleLine]);
  if mMatch.Success then
  begin
    Result.Code := mMatch.Groups[1].Value;
    Result.Text := mMatch.Groups[2].Value;
  end;
  mKind := LowerCase(AKind);
  if mKind.Contains('fatal') then
  begin
    Result.Severity := TAtlasCompilerSeverity.Fatal;
  end
  else if mKind.Contains('error') then
  begin
    Result.Severity := TAtlasCompilerSeverity.Error;
  end
  else if mKind.Contains('warn') then
  begin
    Result.Severity := TAtlasCompilerSeverity.Warning;
  end
  else if mKind.Contains('hint') then
  begin
    Result.Severity := TAtlasCompilerSeverity.Hint;
  end
  else if Result.Code <> '' then
    // Unbekannte Art: nach dem Code.
    case Result.Code[1] of
      'E': Result.Severity := TAtlasCompilerSeverity.Error;
      'W': Result.Severity := TAtlasCompilerSeverity.Warning;
      'H': Result.Severity := TAtlasCompilerSeverity.Hint;
      'F': Result.Severity := TAtlasCompilerSeverity.Fatal;
    else
      Result.Severity := TAtlasCompilerSeverity.Info;
    end
  else
  begin
    Result.Severity := TAtlasCompilerSeverity.Info;
  end;
end;

class function TAtlasCompilerMessages.Resolve(const AMessages: TArray<TAtlasCompilerMessage>;
  const AProjectFile: string; const AKnownFiles: TArray<string>): TArray<TAtlasCompilerMessage>;
var
  mIndex: Integer;
  mName, mKnown, mCandidate: string;
  mFound: Boolean;
begin
  Result := Copy(AMessages);
  for mIndex := 0 to High(Result) do
  begin
    mName := StringReplace(Result[mIndex].FileName, '/', PathDelim, [rfReplaceAll]);
    if (mName = '') or (ExtractFileDrive(mName) <> '') or mName.StartsWith(PathDelim) then
    begin
      Continue;
    end;
    mFound := False;
    for mKnown in AKnownFiles do
    begin
      if SameText(mKnown, mName) or EndsText(PathDelim + mName, mKnown) then
      begin
        Result[mIndex].FileName := mKnown;
        mFound := True;
        Break;
      end;
    end;
    if mFound or (AProjectFile = '') then
    begin
      Continue;
    end;
    mCandidate := ExpandFileName(IncludeTrailingPathDelimiter(ExtractFilePath(AProjectFile)) + mName);
    if FileExists(mCandidate) then
    begin
      Result[mIndex].FileName := mCandidate;
    end;
  end;
end;

class function TAtlasCompilerMessages.SeverityText(ASeverity: TAtlasCompilerSeverity): string;
const
  cTexts: array[TAtlasCompilerSeverity] of string = ('info', 'hint', 'warning', 'error', 'fatal');
begin
  Result := cTexts[ASeverity];
end;

class function TAtlasCompilerMessages.ToJson(const AMessages: TArray<TAtlasCompilerMessage>; const AProject,
  APlatform: string; ASucceeded: Boolean): TJSONObject;
begin
  Result := ToJson(AMessages, AProject, APlatform, ASucceeded, False);
end;

class function TAtlasCompilerMessages.ToJson(const AMessages: TArray<TAtlasCompilerMessage>; const AProject,
  APlatform: string; ASucceeded, ABackground: Boolean): TJSONObject;
var
  mItems: TJSONArray;
  mMessage: TAtlasCompilerMessage;
  mItem: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('project', AProject);
  Result.AddPair('platform', APlatform);
  Result.AddPair('success', TJSONBool.Create(ASucceeded));
  if ABackground then
  begin
    Result.AddPair('background', TJSONBool.Create(True));
  end;
  mItems := TJSONArray.Create;
  Result.AddPair('messages', mItems);
  for mMessage in AMessages do
  begin
    if mMessage.Severity = TAtlasCompilerSeverity.Info then
    begin
      Continue;
    end;
    mItem := TJSONObject.Create;
    mItem.AddPair('file', mMessage.FileName);
    mItem.AddPair('line', TJSONNumber.Create(mMessage.Line));
    mItem.AddPair('column', TJSONNumber.Create(mMessage.Column));
    mItem.AddPair('severity', SeverityText(mMessage.Severity));
    mItem.AddPair('code', mMessage.Code);
    mItem.AddPair('text', mMessage.Text);
    mItems.AddElement(mItem);
  end;
end;

end.
