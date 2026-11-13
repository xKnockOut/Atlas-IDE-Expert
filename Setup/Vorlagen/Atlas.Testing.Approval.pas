unit Atlas.Testing.Approval;

// Vergleichsdateien für DUnitX-Tests („Approval“, #1881). Für Exporte, Berichte,
// erzeugten Code oder JSON: das Ergebnis gegen eine gespeicherte Datei prüfen
// statt mit einem Assert je Zeile. Diese Unit ins Testprojekt kopieren (oder ihren
// Ordner in den Suchpfad aufnehmen); frei verwendbar unter der MIT-Lizenz.
//
//   uses Atlas.Testing.Approval;
//
//   procedure TExportTests.WritesReport;
//   begin
//     TApproval.Verify(TExport.Report(FKunden), 'TExportTests.WritesReport');
//   end;
//
// - Erwartung: <Ordner>\TExportTests.WritesReport.approved.txt (UTF-8). Zeilenenden
//   (CRLF, LF, CR) zählen nicht als Abweichung.
// - Weicht das Ergebnis ab, schreibt Verify daneben ….received.txt und lässt den
//   Test fehlschlagen: „Approval: Abweichung ab Zeile 3, siehe "…received.txt"
//   (erwartet: "…approved.txt")“. Fehlt die approved-Datei, ebenso mit „neu, bitte
//   prüfen“. Stimmt es, löscht Verify eine alte received-Datei.
// - Übernehmen: die received-Datei in approved umbenennen; Atlas bietet dafür an
//   der Testmarke „Als neue Erwartung übernehmen“.
// - Ordner: TApproval.Folder; leer = tests.approvalFolder der nächsten atlas.json
//   über dem Testprogramm (Vorgabe Tests\Erwartet, relativ zu ihrem Ordner), ohne
//   atlas.json neben der nächsten .dproj darüber, sonst neben dem Programm.
// - Veränderliche Teile (Datum, GUID) vorher mit einem TApprovalNormalizer ersetzen.
// - Meldungen deutsch, mit TApproval.English := True englisch; Atlas erkennt beide.
// Nur RTL und DUnitX, ohne Atlas-Packages; übersetzt mit Delphi 12 und neuer.

interface

type
  /// <summary>Ersetzt veränderliche Teile des Ergebnisses (Datum, GUID) vor dem Vergleich.</summary>
  TApprovalNormalizer = reference to function(const AText: string): string;

  {$SCOPEDENUMS ON}
  /// <summary>Ergebnis eines Vergleichs: gleich, abweichend, noch keine Erwartung.</summary>
  TApprovalOutcome = (Same, Different, New);
  {$SCOPEDENUMS OFF}

  TApproval = class
  public const
    cApproved = '.approved';
    cReceived = '.received';
    cDefaultExtension = '.txt';
    cDefaultFolder = 'Tests\Erwartet';
    cSettingsFile = 'atlas.json';
  public
    class var
      /// <summary>Ordner der Vergleichsdateien; '' = aus atlas.json bzw. Vorgabe (siehe oben).</summary>
      Folder: string;
      /// <summary>Meldungen englisch statt deutsch.</summary>
      English: Boolean;
  public
    /// <summary>AText mit LF als einzigem Zeilenende.</summary>
    class function Normalized(const AText: string): string; static;
    /// <summary>Erste abweichende Zeile (ab 1) von AExpected und AActual, beide mit LF; 0 = gleich.</summary>
    class function FirstDifference(const AExpected, AActual: string): Integer; static;
    /// <summary>Ordner aus dem Text AJson einer atlas.json im Ordner ABase (tests.approvalFolder).</summary>
    class function FolderOfSettings(const AJson, ABase: string): string; static;
    /// <summary>Ordner der Vergleichsdateien für ein Testprogramm im Ordner AStart.</summary>
    class function FolderFrom(const AStart: string): string; static;
    /// <summary>Datei AName mit Art AKind (cApproved, cReceived) und Endung AExtension in AFolder.</summary>
    class function FileOf(const AFolder, AName, AKind, AExtension: string): string; static;
    /// <summary>AActual gegen die approved-Datei prüfen; schreibt bzw. löscht die received-Datei. AMessage ist die
    /// Meldung für den Test ('' bei Same).</summary>
    class function Compare(const AActual, AFolder, AName, AExtension: string; out AMessage: string): TApprovalOutcome;
      static;
    /// <summary>Prüft AActual gegen AName.approved.txt; der Test schlägt bei einer Abweichung fehl.</summary>
    class procedure Verify(const AActual, AName: string); overload; static;
    /// <summary>Wie oben mit eigener Endung, z. B. '.json'.</summary>
    class procedure Verify(const AActual, AName, AExtension: string); overload; static;
    /// <summary>Wie oben; ANormalizer bereitet AActual vor dem Vergleich auf.</summary>
    class procedure Verify(const AActual, AName, AExtension: string; const ANormalizer: TApprovalNormalizer);
      overload; static;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  DUnitX.TestFramework;

type
  {$SCOPEDENUMS ON}
  TApprovalText = (Different, New);
  {$SCOPEDENUMS OFF}

const
  cTexts: array[Boolean, TApprovalText] of string = (
    ('Approval: Abweichung ab Zeile %d, siehe "%s" (erwartet: "%s")',
     'Approval: neu, bitte prüfen: "%s" (erwartet: "%s")'),
    ('Approval: difference from line %d, see "%s" (expected: "%s")',
     'Approval: new, please review: "%s" (expected: "%s")'));
  cTestsKey = 'tests';
  cFolderKey = 'approvalFolder';
  cProjectMask = '*.dproj';
  cLf = #10;
  cCr = #13;
  cCrLf = #13#10;

{ Dateien }

/// <summary>Text einer UTF-8-Datei ohne BOM.</summary>
function ReadText(const AFileName: string): string;
var
  mStream: TBytesStream;
  mBytes, mPreamble: TBytes;
  mStart: Integer;
begin
  mStream := TBytesStream.Create;
  try
    mStream.LoadFromFile(AFileName);
    mBytes := Copy(mStream.Bytes, 0, mStream.Size);
  finally
    mStream.Free;
  end;
  mPreamble := TEncoding.UTF8.GetPreamble;
  mStart := Length(mPreamble);
  if (Length(mBytes) < mStart) or not CompareMem(@mBytes[0], @mPreamble[0], mStart) then
  begin
    mStart := 0;
  end;
  Result := TEncoding.UTF8.GetString(mBytes, mStart, Length(mBytes) - mStart);
end;

/// <summary>AText als UTF-8 ohne BOM mit den Zeilenenden des Systems schreiben.</summary>
procedure WriteText(const AFileName, AText: string);
var
  mStream: TFileStream;
  mBytes: TBytes;
begin
  ForceDirectories(ExtractFileDir(AFileName));
  mBytes := TEncoding.UTF8.GetBytes(StringReplace(AText, cLf, sLineBreak, [rfReplaceAll]));
  mStream := TFileStream.Create(AFileName, fmCreate);
  try
    if Length(mBytes) > 0 then
    begin
      mStream.WriteBuffer(mBytes[0], Length(mBytes));
    end;
  finally
    mStream.Free;
  end;
end;

/// <summary>Gibt es in AFolder eine Projektdatei (.dproj)?</summary>
function HasProject(const AFolder: string): Boolean;
var
  mSearch: TSearchRec;
begin
  Result := FindFirst(IncludeTrailingPathDelimiter(AFolder) + cProjectMask, faAnyFile, mSearch) = 0;
  if Result then
  begin
    FindClose(mSearch);
  end;
end;

/// <summary>Pfad mit dem Trennzeichen des Systems.</summary>
function NativePath(const APath: string): string;
begin
  Result := StringReplace(StringReplace(APath, '/', PathDelim, [rfReplaceAll]), '\', PathDelim, [rfReplaceAll]);
end;

/// <summary>APath relativ zu ABase auflösen; absolute Pfade bleiben.</summary>
function Resolved(const APath, ABase: string): string;
begin
  Result := NativePath(APath);
  if (ExtractFileDrive(Result) = '') and not Result.StartsWith(PathDelim) then
  begin
    Result := ExpandFileName(IncludeTrailingPathDelimiter(ABase) + Result);
  end;
end;

{ TApproval }

class function TApproval.Normalized(const AText: string): string;
begin
  // Zuerst das Paar, sonst würde aus CRLF zweimal LF.
  Result := StringReplace(StringReplace(AText, cCrLf, cLf, [rfReplaceAll]), cCr, cLf, [rfReplaceAll]);
end;

class function TApproval.FirstDifference(const AExpected, AActual: string): Integer;
var
  mExpected, mActual: TArray<string>;
  mLine: Integer;
begin
  Result := 0;
  if AExpected = AActual then
  begin
    Exit;
  end;
  mExpected := AExpected.Split([cLf]);
  mActual := AActual.Split([cLf]);
  mLine := 0;
  while (mLine < Length(mExpected)) and (mLine < Length(mActual)) and (mExpected[mLine] = mActual[mLine]) do
  begin
    Inc(mLine);
  end;
  Result := mLine + 1;
end;

class function TApproval.FolderOfSettings(const AJson, ABase: string): string;
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
  Result := Resolved(Result, ABase);
end;

class function TApproval.FolderFrom(const AStart: string): string;
var
  mFolder, mParent, mProject: string;
begin
  mFolder := ExcludeTrailingPathDelimiter(ExpandFileName(AStart));
  mProject := '';
  // Die nächste atlas.json gilt; ohne sie der Ordner der nächsten Projektdatei.
  while mFolder <> '' do
  begin
    if FileExists(IncludeTrailingPathDelimiter(mFolder) + cSettingsFile) then
    begin
      Exit(FolderOfSettings(ReadText(IncludeTrailingPathDelimiter(mFolder) + cSettingsFile), mFolder));
    end;
    if (mProject = '') and HasProject(mFolder) then
    begin
      mProject := mFolder;
    end;
    mParent := ExcludeTrailingPathDelimiter(ExtractFileDir(mFolder));
    if (mParent = mFolder) or (mParent = '') then
    begin
      Break;
    end;
    mFolder := mParent;
  end;
  if mProject = '' then
  begin
    mProject := ExpandFileName(AStart);
  end;
  Result := Resolved(cDefaultFolder, mProject);
end;

class function TApproval.FileOf(const AFolder, AName, AKind, AExtension: string): string;
var
  mExtension: string;
begin
  mExtension := AExtension;
  if mExtension = '' then
  begin
    mExtension := cDefaultExtension;
  end
  else if not mExtension.StartsWith('.') then
  begin
    mExtension := '.' + mExtension;
  end;
  Result := IncludeTrailingPathDelimiter(AFolder) + AName + AKind + mExtension;
end;

class function TApproval.Compare(const AActual, AFolder, AName, AExtension: string;
  out AMessage: string): TApprovalOutcome;
var
  mApproved, mReceived, mActual: string;
  mLine: Integer;
begin
  AMessage := '';
  mApproved := FileOf(AFolder, AName, cApproved, AExtension);
  mReceived := FileOf(AFolder, AName, cReceived, AExtension);
  mActual := Normalized(AActual);
  mLine := 1;
  Result := TApprovalOutcome.New;
  if FileExists(mApproved) then
  begin
    mLine := FirstDifference(Normalized(ReadText(mApproved)), mActual);
    Result := TApprovalOutcome.Different;
  end;
  if mLine = 0 then
  begin
    // Gleich: eine received-Datei aus einem früheren Lauf ist überholt.
    if FileExists(mReceived) then
    begin
      DeleteFile(mReceived);
    end;
    Exit(TApprovalOutcome.Same);
  end;
  WriteText(mReceived, mActual);
  if Result = TApprovalOutcome.New then
  begin
    AMessage := Format(cTexts[English, TApprovalText.New], [mReceived, mApproved]);
  end
  else
  begin
    AMessage := Format(cTexts[English, TApprovalText.Different], [mLine, mReceived, mApproved]);
  end;
end;

class procedure TApproval.Verify(const AActual, AName: string);
begin
  Verify(AActual, AName, cDefaultExtension, nil);
end;

class procedure TApproval.Verify(const AActual, AName, AExtension: string);
begin
  Verify(AActual, AName, AExtension, nil);
end;

class procedure TApproval.Verify(const AActual, AName, AExtension: string; const ANormalizer: TApprovalNormalizer);
var
  mActual, mFolder, mMessage: string;
begin
  mActual := AActual;
  if Assigned(ANormalizer) then
  begin
    mActual := ANormalizer(mActual);
  end;
  mFolder := Folder;
  if mFolder = '' then
  begin
    mFolder := FolderFrom(ExtractFileDir(ParamStr(0)));
  end;
  if Compare(mActual, mFolder, AName, AExtension, mMessage) <> TApprovalOutcome.Same then
  begin
    Assert.Fail(mMessage);
  end;
end;

end.
