unit Atlas.Core.Tests.Approval;

// Vergleichsdateien im Plugin (#1881, tests.approvalFiles), ohne VCL und Open
// Tools API, auch unter FPC prüfbar:
// - Parse erkennt die Meldung der Hilfs-Unit Atlas.Testing.Approval
//   (Setup/Vorlagen) in einem fehlgeschlagenen Test: „Approval:“, bei einer
//   Abweichung die Zeile, dann die received- und die approved-Datei in
//   Anführungszeichen (deutsch und englisch).
// - Accept übernimmt die received-Datei als neue Erwartung (approved
//   ersetzen, received weg); ReadSide liest eine Seite für den Vergleich.
// - FolderOf: Ordner der Vergleichsdateien eines Testprojekts wie in der
//   Hilfs-Unit (nächste atlas.json mit tests.approvalFolder, sonst
//   Tests\Erwartet neben der Projektdatei). Die Hilfs-Unit hängt bewusst an
//   nichts von Atlas, daher die zweite Fassung hier.
// - Leftovers: liegengebliebene received-Dateien eines Ordners (rekursiv);
//   IgnoreFileFrom und HasIgnoreEntry für den Vorschlag, das Muster
//   *.received.* in die .gitignore aufzunehmen.

interface

{$SCOPEDENUMS ON}

type
  /// <summary>Art der Meldung: Abweichung zur approved-Datei oder noch keine approved-Datei.</summary>
  TAtlasApprovalKind = (Different, Added);
  /// <summary>Ergebnis von Accept: übernommen, received-Datei fehlt, Dateisystem verweigert.</summary>
  TAtlasApprovalAccept = (Done, Missing, Failed);

  TAtlasApprovalHit = record
    Kind: TAtlasApprovalKind;
    /// <summary>Erste abweichende Zeile (ab 1); 0 bei Added.</summary>
    Line: Integer;
    Received: string;
    Approved: string;
  end;

  TAtlasTestApproval = class
  public const
    cPrefix = 'Approval:';
    cReceivedPart = '.received.';
    cApprovedPart = '.approved.';
    cIgnorePattern = '*.received.*';
    cDefaultFolder = 'Tests\Erwartet';
    cSettingsFile = 'atlas.json';
    cIgnoreFile = '.gitignore';
  public
    /// <summary>Meldung der Hilfs-Unit in AMessage; False ohne bzw. ohne beide Dateien.</summary>
    class function Parse(const AMessage: string; out AHit: TAtlasApprovalHit): Boolean; static;
    /// <summary>Text einer Seite (UTF-8, Zeilenenden LF); '' ohne Datei.</summary>
    class function ReadSide(const AFileName: string): string; static;
    /// <summary>received-Datei von AHit wird die approved-Datei; die received-Datei verschwindet.</summary>
    class function Accept(const AHit: TAtlasApprovalHit): TAtlasApprovalAccept; static;
    /// <summary>Ordner der Vergleichsdateien aus dem Inhalt einer atlas.json (AJson) im Ordner ABase.</summary>
    class function FolderOfSettings(const AJson, ABase: string): string; static;
    /// <summary>Ordner der Vergleichsdateien des Testprojekts AProjectFile.</summary>
    class function FolderOf(const AProjectFile: string): string; static;
    /// <summary>received-Dateien in AFolder und darunter, sortiert; leer ohne Ordner.</summary>
    class function Leftovers(const AFolder: string): TArray<string>; static;
    /// <summary>Nächste .gitignore ab AStart aufwärts, höchstens bis zum Ordner mit .git; '' ohne.</summary>
    class function IgnoreFileFrom(const AStart: string): string; static;
    /// <summary>Hat der Inhalt einer .gitignore schon eine Zeile für received-Dateien?</summary>
    class function HasIgnoreEntry(const AText: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.Generics.Collections;

const
  cQuote = '"';
  cTestsKey = 'tests';
  cFolderKey = 'approvalFolder';
  cGitFolder = '.git';
  cLf = #10;
  cCr = #13;
  cCrLf = #13#10;
  cComment = '#';

/// <summary>Text zwischen dem nächsten Paar Anführungszeichen ab AFrom (1-basiert); AFrom danach hinter dem
/// schließenden. False ohne Paar.</summary>
function NextQuoted(const AText: string; var AFrom: Integer; out AValue: string): Boolean;
var
  mOpen, mClose: Integer;
begin
  AValue := '';
  mOpen := Pos(cQuote, AText, AFrom);
  mClose := 0;
  if mOpen > 0 then
  begin
    mClose := Pos(cQuote, AText, mOpen + 1);
  end;
  Result := mClose > 0;
  if Result then
  begin
    AValue := Copy(AText, mOpen + 1, mClose - mOpen - 1);
    AFrom := mClose + 1;
  end;
end;

/// <summary>Erste Zahl in AText zwischen AFrom und ATo (1-basiert, ATo ausgeschlossen); 0 ohne.</summary>
function FirstNumber(const AText: string; AFrom, ATo: Integer): Integer;
var
  mIndex, mStart: Integer;
begin
  Result := 0;
  mIndex := AFrom;
  while (mIndex < ATo) and not CharInSet(AText[mIndex], ['0'..'9']) do
  begin
    Inc(mIndex);
  end;
  mStart := mIndex;
  while (mIndex < ATo) and CharInSet(AText[mIndex], ['0'..'9']) do
  begin
    Inc(mIndex);
  end;
  if mIndex > mStart then
  begin
    Result := StrToIntDef(Copy(AText, mStart, mIndex - mStart), 0);
  end;
end;

{ TAtlasTestApproval }

class function TAtlasTestApproval.Parse(const AMessage: string; out AHit: TAtlasApprovalHit): Boolean;
var
  mStart, mFrom: Integer;
begin
  AHit := Default(TAtlasApprovalHit);
  mStart := Pos(cPrefix, AMessage);
  Result := False;
  if mStart = 0 then
  begin
    Exit;
  end;
  mFrom := mStart + Length(cPrefix);
  if not NextQuoted(AMessage, mFrom, AHit.Received) or not NextQuoted(AMessage, mFrom, AHit.Approved) then
  begin
    AHit := Default(TAtlasApprovalHit);
    Exit;
  end;
  // Die Zeile steht nur bei einer Abweichung vor der ersten Datei.
  AHit.Line := FirstNumber(AMessage, mStart + Length(cPrefix), Pos(cQuote, AMessage, mStart));
  if AHit.Line > 0 then
  begin
    AHit.Kind := TAtlasApprovalKind.Different;
  end
  else
  begin
    AHit.Kind := TAtlasApprovalKind.Added;
  end;
  Result := AHit.Received.ToLower.Contains(cReceivedPart) and AHit.Approved.ToLower.Contains(cApprovedPart);
end;

class function TAtlasTestApproval.ReadSide(const AFileName: string): string;
begin
  Result := '';
  if (AFileName <> '') and FileExists(AFileName) then
  begin
    // TEncoding.UTF8 überspringt eine BOM; Zeilenenden wie in der Hilfs-Unit angleichen (zuerst das Paar).
    Result := StringReplace(StringReplace(TFile.ReadAllText(AFileName, TEncoding.UTF8), cCrLf, cLf, [rfReplaceAll]),
      cCr, cLf, [rfReplaceAll]);
  end;
end;

class function TAtlasTestApproval.Accept(const AHit: TAtlasApprovalHit): TAtlasApprovalAccept;
begin
  if (AHit.Received = '') or not FileExists(AHit.Received) then
  begin
    Exit(TAtlasApprovalAccept.Missing);
  end;
  try
    ForceDirectories(ExtractFileDir(AHit.Approved));
    if FileExists(AHit.Approved) then
    begin
      TFile.Delete(AHit.Approved);
    end;
    TFile.Move(AHit.Received, AHit.Approved);
    Result := TAtlasApprovalAccept.Done;
  except
    on EInOutError do
      // Schreibgeschützt oder gesperrt: Der Aufrufer meldet es; beide Dateien bleiben, wie sie sind.
      Result := TAtlasApprovalAccept.Failed;
  end;
end;

class function TAtlasTestApproval.FolderOfSettings(const AJson, ABase: string): string;
var
  mRoot, mTests, mValue: TJSONValue;
begin
  Result := cDefaultFolder;
  mRoot := TJSONObject.ParseJSONValue(AJson);
  try
    if mRoot is TJSONObject then
    begin
      mTests := TJSONObject(mRoot).GetValue(cTestsKey);
      if mTests is TJSONObject then
      begin
        mValue := TJSONObject(mTests).GetValue(cFolderKey);
        if (mValue is TJSONString) and (Trim(mValue.Value) <> '') then
        begin
          Result := mValue.Value;
        end;
      end;
    end;
  finally
    mRoot.Free;
  end;
  Result := StringReplace(StringReplace(Result, '/', PathDelim, [rfReplaceAll]), '\', PathDelim, [rfReplaceAll]);
  if (ExtractFileDrive(Result) = '') and not Result.StartsWith(PathDelim) then
  begin
    Result := ExpandFileName(IncludeTrailingPathDelimiter(ABase) + Result);
  end;
end;

class function TAtlasTestApproval.FolderOf(const AProjectFile: string): string;
var
  mProject, mFolder, mParent, mSettings: string;
begin
  mProject := ExtractFileDir(ExpandFileName(StringReplace(AProjectFile, '/', PathDelim, [rfReplaceAll])));
  mFolder := mProject;
  while mFolder <> '' do
  begin
    mSettings := IncludeTrailingPathDelimiter(mFolder) + cSettingsFile;
    if FileExists(mSettings) then
    begin
      Exit(FolderOfSettings(TFile.ReadAllText(mSettings, TEncoding.UTF8), mFolder));
    end;
    mParent := ExcludeTrailingPathDelimiter(ExtractFileDir(mFolder));
    if (mParent = mFolder) or (mParent = '') then
    begin
      Break;
    end;
    mFolder := mParent;
  end;
  Result := FolderOfSettings('', mProject);
end;

class function TAtlasTestApproval.Leftovers(const AFolder: string): TArray<string>;
var
  mList: TList<string>;
  mName: string;
begin
  Result := nil;
  if (AFolder = '') or not DirectoryExists(AFolder) then
  begin
    Exit;
  end;
  mList := TList<string>.Create;
  try
    for mName in TDirectory.GetFiles(AFolder, '*', TSearchOption.soAllDirectories) do
    begin
      if ExtractFileName(mName).ToLower.Contains(cReceivedPart) then
      begin
        mList.Add(mName);
      end;
    end;
    // Pfade sind eindeutig, die Sortierung daher stabil genug.
    mList.Sort;
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

class function TAtlasTestApproval.IgnoreFileFrom(const AStart: string): string;
var
  mFolder, mParent: string;
begin
  Result := '';
  mFolder := ExcludeTrailingPathDelimiter(ExpandFileName(AStart));
  while mFolder <> '' do
  begin
    if FileExists(IncludeTrailingPathDelimiter(mFolder) + cIgnoreFile) then
    begin
      Exit(IncludeTrailingPathDelimiter(mFolder) + cIgnoreFile);
    end;
    mParent := ExcludeTrailingPathDelimiter(ExtractFileDir(mFolder));
    if DirectoryExists(IncludeTrailingPathDelimiter(mFolder) + cGitFolder) or (mParent = mFolder) or
      (mParent = '') then
    begin
      Break;
    end;
    mFolder := mParent;
  end;
end;

class function TAtlasTestApproval.HasIgnoreEntry(const AText: string): Boolean;
var
  mLine, mEntry: string;
begin
  Result := False;
  for mLine in StringReplace(AText, cCr, '', [rfReplaceAll]).Split([cLf]) do
  begin
    mEntry := Trim(mLine);
    if (mEntry <> '') and not mEntry.StartsWith(cComment) and mEntry.ToLower.Contains(cReceivedPart) then
    begin
      Exit(True);
    end;
  end;
end;

end.
