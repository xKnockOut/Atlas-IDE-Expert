unit Atlas.Core.Tests.ProjectChoice;

// Gemerkte Wahl des Testprojekts (#585): Gehört eine Testunit zu mehreren
// Testprojekten der Projektgruppe (oder gibt es ohne Testunit mehrere),
// fragt Atlas einmal und merkt sich die Wahl für genau diese Kandidaten.
// Ohne VCL und Open Tools API; das Fragen macht die IDE-Schicht.
// - Schlüssel: die Dateien der Kandidaten klein, sortiert, mit „|“ verbunden;
//   dieselbe Auswahl fragt nicht wieder, eine andere (neues Testprojekt in
//   der Gruppe) schon.
// - Datei %LOCALAPPDATA%\Atlas\test-projects.json, Format 1 (UTF-8):
//     {"format": 1, "choices": [{"candidates": "c:\\a.dproj|c:\\b.dproj",
//       "project": "C:\\b.dproj"}]}
//   Neueste Wahl zuerst, höchstens cMaxEntries; ein höheres Format bleibt
//   unangetastet. Lesen und Schreiben über TAtlasDataFile (Bericht N3):
//   atomar ersetzt (früher Löschen und Umbenennen), eine unbrauchbare Datei
//   liegt danach als .defekt daneben, eine gesperrte wird nicht überschrieben.

interface

uses
  System.SysUtils,
  Atlas.Core.Files.DataFile;

type
  TAtlasTestProjectChoice = record
    /// <summary>Schlüssel der Kandidaten (KeyOf).</summary>
    Key: string;
    /// <summary>Gewähltes Testprojekt (.dproj).</summary>
    Project: string;
  end;

  TAtlasTestProjectChoices = class
  public const
    cFormat = 1;
    cFileName = 'test-projects.json';
    cMaxEntries = 100;
  public
    /// <summary>Schlüssel einer Auswahl: Dateien klein, sortiert, ohne doppelte, mit „|“ verbunden.</summary>
    class function KeyOf(const ACandidates: TArray<string>): string; static;
    /// <summary>Gemerkte Wahl aus dem Text der Datei; leer bei ungültigem Inhalt oder höherem Format.</summary>
    class function Parse(const AText: string): TArray<TAtlasTestProjectChoice>; static;
    /// <summary>Format der Datei (0 ohne oder bei ungültigem Inhalt).</summary>
    class function FormatOf(const AText: string): Integer; static;
    /// <summary>Text der Datei (eingerückt, CRLF).</summary>
    class function ToJson(const AChoices: TArray<TAtlasTestProjectChoice>): string; static;
    /// <summary>Gemerkte Wahl; leer ohne Datei, bei unbrauchbarer (dann als .defekt beiseitegelegt) oder
    /// gesperrter. Ergebnis Kept: vorhanden, aber nicht gelesen; dann nicht speichern.</summary>
    class function Load(const AFile: string; out AChoices: TArray<TAtlasTestProjectChoice>): TAtlasDataLoad;
      overload; static;
    class function Load(const AFile: string): TArray<TAtlasTestProjectChoice>; overload; static;
    /// <summary>Ersetzt die Datei atomar; False bei Fehler (einmal protokolliert), bei höherem Format der
    /// vorhandenen oder wenn sie gerade nicht lesbar ist.</summary>
    class function Save(const AFile: string; const AChoices: TArray<TAtlasTestProjectChoice>): Boolean; static;
    /// <summary>Index des gemerkten Projekts in ACandidates; bei einem einzigen Kandidaten 0, sonst -1, wenn für
    /// diese Kandidaten nichts gemerkt ist oder das gemerkte Projekt fehlt.</summary>
    class function Pick(const AChoices: TArray<TAtlasTestProjectChoice>;
      const ACandidates: TArray<string>): Integer; static;
    /// <summary>Wahl AProject für ACandidates merken (vorne, ersetzt eine frühere für dieselben Kandidaten).
    /// </summary>
    class procedure Remember(var AChoices: TArray<TAtlasTestProjectChoice>; const ACandidates: TArray<string>;
      const AProject: string); static;
  end;

implementation

uses
  System.JSON,
  System.Generics.Collections,
  Atlas.Text.Json;

function Quote(const AText: string): string;
var
  mValue: TJSONString;
begin
  mValue := TJSONString.Create(AText);
  try
    Result := mValue.ToJSON;
  finally
    mValue.Free;
  end;
end;

{ TAtlasTestProjectChoices }

class function TAtlasTestProjectChoices.KeyOf(const ACandidates: TArray<string>): string;
var
  mItems: TList<string>;
  mCandidate, mItem: string;
begin
  mItems := TList<string>.Create;
  try
    for mCandidate in ACandidates do
    begin
      mItem := AnsiLowerCase(Trim(mCandidate));
      if (mItem <> '') and not mItems.Contains(mItem) then
      begin
        mItems.Add(mItem);
      end;
    end;
    mItems.Sort;
    Result := '';
    for mItem in mItems do
    begin
      if Result <> '' then
      begin
        Result := Result + '|';
      end;
      Result := Result + mItem;
    end;
  finally
    mItems.Free;
  end;
end;

class function TAtlasTestProjectChoices.FormatOf(const AText: string): Integer;
var
  mRoot, mValue: TJSONValue;
begin
  Result := 0;
  if Trim(AText) = '' then
  begin
    Exit;
  end;
  mRoot := TJSONObject.ParseJSONValue(AText);
  try
    if not (mRoot is TJSONObject) then
    begin
      Exit;
    end;
    mValue := TJSONObject(mRoot).GetValue('format');
    if mValue is TJSONNumber then
    begin
      Result := TJSONNumber(mValue).AsInt;
    end;
  finally
    mRoot.Free;
  end;
end;

class function TAtlasTestProjectChoices.Parse(const AText: string): TArray<TAtlasTestProjectChoice>;
var
  mRoot, mValue: TJSONValue;
  mIndex: Integer;
  mChoice: TAtlasTestProjectChoice;
begin
  Result := nil;
  if Trim(AText) = '' then
  begin
    Exit;
  end;
  mRoot := TJSONObject.ParseJSONValue(AText);
  try
    if not (mRoot is TJSONObject) then
    begin
      Exit;
    end;
    mValue := TJSONObject(mRoot).GetValue('format');
    if (mValue is TJSONNumber) and (TJSONNumber(mValue).AsInt > cFormat) then
    begin
      Exit;
    end;
    mValue := TJSONObject(mRoot).GetValue('choices');
    if not (mValue is TJSONArray) then
    begin
      Exit;
    end;
    for mIndex := 0 to TJSONArray(mValue).Count - 1 do
    begin
      if TJSONArray(mValue).Items[mIndex] is TJSONObject then
      begin
        mChoice.Key := TJsonRead.Text(TJSONObject(TJSONArray(mValue).Items[mIndex]), 'candidates');
        mChoice.Project := TJsonRead.Text(TJSONObject(TJSONArray(mValue).Items[mIndex]), 'project');
        if (mChoice.Key <> '') and (mChoice.Project <> '') and (Length(Result) < cMaxEntries) then
        begin
          Result := Result + [mChoice];
        end;
      end;
    end;
  finally
    mRoot.Free;
  end;
end;

class function TAtlasTestProjectChoices.ToJson(const AChoices: TArray<TAtlasTestProjectChoice>): string;
const
  cNewLine = #13#10;
var
  mLines: TStringBuilder;
  mIndex: Integer;
begin
  mLines := TStringBuilder.Create;
  try
    mLines.Append('{' + cNewLine);
    mLines.Append('  "format": ' + IntToStr(cFormat) + ',' + cNewLine);
    mLines.Append('  "choices": [');
    for mIndex := 0 to High(AChoices) do
    begin
      if mIndex > 0 then
      begin
        mLines.Append(',');
      end;
      mLines.Append(cNewLine + '    {"candidates": ' + Quote(AChoices[mIndex].Key) + ', "project": ' +
        Quote(AChoices[mIndex].Project) + '}');
    end;
    if Length(AChoices) > 0 then
    begin
      mLines.Append(cNewLine + '  ');
    end;
    mLines.Append(']' + cNewLine + '}' + cNewLine);
    Result := mLines.ToString;
  finally
    mLines.Free;
  end;
end;

class function TAtlasTestProjectChoices.Load(const AFile: string;
  out AChoices: TArray<TAtlasTestProjectChoice>): TAtlasDataLoad;
var
  mChoices: TArray<TAtlasTestProjectChoice>;
begin
  AChoices := nil;
  if AFile = '' then
  begin
    Exit(TAtlasDataLoad.Missing);
  end;
  mChoices := nil;
  Result := TAtlasDataFile.Load(AFile, 'Wahl des Testprojekts',
    function(const AText: string): Boolean
    begin
      mChoices := Parse(AText);
      // ToJson schreibt immer "format"; ohne ist die Datei unbrauchbar. Ein höheres Format bleibt (Save
      // überschreibt es nicht).
      Result := FormatOf(AText) >= 1;
    end);
  if Result = TAtlasDataLoad.Loaded then
  begin
    AChoices := mChoices;
  end;
end;

class function TAtlasTestProjectChoices.Load(const AFile: string): TArray<TAtlasTestProjectChoice>;
begin
  Load(AFile, Result);
end;

class function TAtlasTestProjectChoices.Save(const AFile: string;
  const AChoices: TArray<TAtlasTestProjectChoice>): Boolean;
var
  mText: string;
begin
  Result := False;
  if AFile = '' then
  begin
    Exit;
  end;
  try
    // Eine neuere Fassung hat die Datei geschrieben oder sie ist gerade nicht lesbar: nicht überschreiben.
    if FileExists(AFile) and (not TAtlasDataFile.TryRead(AFile, mText) or (FormatOf(mText) > cFormat)) then
    begin
      Exit;
    end;
    TAtlasDataFile.Write(AFile, ToJson(AChoices));
    Result := True;
  except
    on E: Exception do
      TAtlasDataFile.ReportNotWritten('Wahl des Testprojekts', E);
  end;
end;

class function TAtlasTestProjectChoices.Pick(const AChoices: TArray<TAtlasTestProjectChoice>;
  const ACandidates: TArray<string>): Integer;
var
  mKey: string;
  mChoice: TAtlasTestProjectChoice;
  mIndex: Integer;
begin
  if Length(ACandidates) = 1 then
  begin
    Exit(0);
  end;
  Result := -1;
  if Length(ACandidates) = 0 then
  begin
    Exit;
  end;
  mKey := KeyOf(ACandidates);
  for mChoice in AChoices do
  begin
    if mChoice.Key = mKey then
    begin
      for mIndex := 0 to High(ACandidates) do
      begin
        if SameText(Trim(ACandidates[mIndex]), Trim(mChoice.Project)) then
        begin
          Exit(mIndex);
        end;
      end;
      Exit;
    end;
  end;
end;

class procedure TAtlasTestProjectChoices.Remember(var AChoices: TArray<TAtlasTestProjectChoice>;
  const ACandidates: TArray<string>; const AProject: string);
var
  mChoice, mFresh: TAtlasTestProjectChoice;
  mKept: TArray<TAtlasTestProjectChoice>;
begin
  mFresh.Key := KeyOf(ACandidates);
  mFresh.Project := Trim(AProject);
  if (mFresh.Key = '') or (mFresh.Project = '') then
  begin
    Exit;
  end;
  mKept := [mFresh];
  for mChoice in AChoices do
  begin
    if (mChoice.Key <> mFresh.Key) and (Length(mKept) < cMaxEntries) then
    begin
      mKept := mKept + [mChoice];
    end;
  end;
  AChoices := mKept;
end;

end.
