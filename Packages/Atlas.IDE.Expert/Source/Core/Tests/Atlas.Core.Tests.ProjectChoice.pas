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
//   Neueste Wahl zuerst, höchstens MaxEntries; ein höheres Format bleibt
//   unangetastet.

interface

uses
  System.SysUtils;

type
  TAtlasTestProjectChoice = record
    /// <summary>Schlüssel der Kandidaten (KeyOf).</summary>
    Key: string;
    /// <summary>Gewähltes Testprojekt (.dproj).</summary>
    Project: string;
  end;

  TAtlasTestProjectChoices = class
  public const
    Format = 1;
    FileName = 'test-projects.json';
    MaxEntries = 100;
  public
    /// <summary>Schlüssel einer Auswahl: Dateien klein, sortiert, ohne doppelte, mit „|“ verbunden.</summary>
    class function KeyOf(const ACandidates: TArray<string>): string; static;
    /// <summary>Gemerkte Wahl aus dem Text der Datei; leer bei ungültigem Inhalt oder höherem Format.</summary>
    class function Parse(const AText: string): TArray<TAtlasTestProjectChoice>; static;
    /// <summary>Format der Datei (0 ohne oder bei ungültigem Inhalt).</summary>
    class function FormatOf(const AText: string): Integer; static;
    /// <summary>Text der Datei (eingerückt, CRLF).</summary>
    class function ToJson(const AChoices: TArray<TAtlasTestProjectChoice>): string; static;
    class function Load(const AFile: string): TArray<TAtlasTestProjectChoice>; static;
    /// <summary>Schreiben über eine temporäre Datei; False bei Fehler oder höherem Format der vorhandenen.</summary>
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
  System.IOUtils;

function Quote(const AText: string): string;
var
  Value: TJSONString;
begin
  Value := TJSONString.Create(AText);
  try
    Result := Value.ToJSON;
  finally
    Value.Free;
  end;
end;

function StringOf(AObject: TJSONObject; const AName: string): string;
var
  Value: TJSONValue;
begin
  Result := '';
  Value := AObject.GetValue(AName);
  if Value is TJSONString then
    Result := TJSONString(Value).Value;
end;

{ TAtlasTestProjectChoices }

class function TAtlasTestProjectChoices.KeyOf(const ACandidates: TArray<string>): string;
var
  Items: TList<string>;
  Candidate, Item: string;
begin
  Items := TList<string>.Create;
  try
    for Candidate in ACandidates do
    begin
      Item := AnsiLowerCase(Trim(Candidate));
      if (Item <> '') and not Items.Contains(Item) then
        Items.Add(Item);
    end;
    Items.Sort;
    Result := '';
    for Item in Items do
    begin
      if Result <> '' then
        Result := Result + '|';
      Result := Result + Item;
    end;
  finally
    Items.Free;
  end;
end;

class function TAtlasTestProjectChoices.FormatOf(const AText: string): Integer;
var
  Root, Value: TJSONValue;
begin
  Result := 0;
  if Trim(AText) = '' then
    Exit;
  Root := TJSONObject.ParseJSONValue(AText);
  try
    if not (Root is TJSONObject) then
      Exit;
    Value := TJSONObject(Root).GetValue('format');
    if Value is TJSONNumber then
      Result := TJSONNumber(Value).AsInt;
  finally
    Root.Free;
  end;
end;

class function TAtlasTestProjectChoices.Parse(const AText: string): TArray<TAtlasTestProjectChoice>;
var
  Root, Value: TJSONValue;
  Index: Integer;
  Choice: TAtlasTestProjectChoice;
begin
  Result := nil;
  if Trim(AText) = '' then
    Exit;
  Root := TJSONObject.ParseJSONValue(AText);
  try
    if not (Root is TJSONObject) then
      Exit;
    Value := TJSONObject(Root).GetValue('format');
    if (Value is TJSONNumber) and (TJSONNumber(Value).AsInt > Format) then
      Exit;
    Value := TJSONObject(Root).GetValue('choices');
    if not (Value is TJSONArray) then
      Exit;
    for Index := 0 to TJSONArray(Value).Count - 1 do
      if TJSONArray(Value).Items[Index] is TJSONObject then
      begin
        Choice.Key := StringOf(TJSONObject(TJSONArray(Value).Items[Index]), 'candidates');
        Choice.Project := StringOf(TJSONObject(TJSONArray(Value).Items[Index]), 'project');
        if (Choice.Key <> '') and (Choice.Project <> '') and (Length(Result) < MaxEntries) then
          Result := Result + [Choice];
      end;
  finally
    Root.Free;
  end;
end;

class function TAtlasTestProjectChoices.ToJson(const AChoices: TArray<TAtlasTestProjectChoice>): string;
const
  NewLine = #13#10;
var
  Lines: TStringBuilder;
  Index: Integer;
begin
  Lines := TStringBuilder.Create;
  try
    Lines.Append('{' + NewLine);
    Lines.Append('  "format": ' + IntToStr(Format) + ',' + NewLine);
    Lines.Append('  "choices": [');
    for Index := 0 to High(AChoices) do
    begin
      if Index > 0 then
        Lines.Append(',');
      Lines.Append(NewLine + '    {"candidates": ' + Quote(AChoices[Index].Key) + ', "project": ' +
        Quote(AChoices[Index].Project) + '}');
    end;
    if Length(AChoices) > 0 then
      Lines.Append(NewLine + '  ');
    Lines.Append(']' + NewLine + '}' + NewLine);
    Result := Lines.ToString;
  finally
    Lines.Free;
  end;
end;

class function TAtlasTestProjectChoices.Load(const AFile: string): TArray<TAtlasTestProjectChoice>;
begin
  Result := nil;
  if (AFile = '') or not FileExists(AFile) then
    Exit;
  try
    Result := Parse(TFile.ReadAllText(AFile, TEncoding.UTF8));
  except
    // Gesperrt oder unlesbar: wie ohne Datei.
    on Exception do
      Result := nil;
  end;
end;

class function TAtlasTestProjectChoices.Save(const AFile: string;
  const AChoices: TArray<TAtlasTestProjectChoice>): Boolean;
var
  Temp: string;
begin
  Result := False;
  if AFile = '' then
    Exit;
  try
    // Eine neuere Fassung hat die Datei geschrieben: nicht überschreiben.
    if FileExists(AFile) and (FormatOf(TFile.ReadAllText(AFile, TEncoding.UTF8)) > Format) then
      Exit;
    ForceDirectories(ExtractFileDir(AFile));
    Temp := AFile + '.tmp';
    TFile.WriteAllText(Temp, ToJson(AChoices), TEncoding.UTF8);
    if FileExists(AFile) then
      System.SysUtils.DeleteFile(AFile);
    Result := RenameFile(Temp, AFile);
  except
    on Exception do
      Result := False;
  end;
end;

class function TAtlasTestProjectChoices.Pick(const AChoices: TArray<TAtlasTestProjectChoice>;
  const ACandidates: TArray<string>): Integer;
var
  Key: string;
  Choice: TAtlasTestProjectChoice;
  Index: Integer;
begin
  if Length(ACandidates) = 1 then
    Exit(0);
  Result := -1;
  if Length(ACandidates) = 0 then
    Exit;
  Key := KeyOf(ACandidates);
  for Choice in AChoices do
    if Choice.Key = Key then
    begin
      for Index := 0 to High(ACandidates) do
        if SameText(Trim(ACandidates[Index]), Trim(Choice.Project)) then
          Exit(Index);
      Exit;
    end;
end;

class procedure TAtlasTestProjectChoices.Remember(var AChoices: TArray<TAtlasTestProjectChoice>;
  const ACandidates: TArray<string>; const AProject: string);
var
  Choice, Fresh: TAtlasTestProjectChoice;
  Kept: TArray<TAtlasTestProjectChoice>;
begin
  Fresh.Key := KeyOf(ACandidates);
  Fresh.Project := Trim(AProject);
  if (Fresh.Key = '') or (Fresh.Project = '') then
    Exit;
  Kept := [Fresh];
  for Choice in AChoices do
    if (Choice.Key <> Fresh.Key) and (Length(Kept) < MaxEntries) then
      Kept := Kept + [Choice];
  AChoices := Kept;
end;

end.
