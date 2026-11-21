unit Atlas.Tests.Files;

// Testhilfe: Dateien der Testdaten unter Tests\ finden und Dateien eines gedachten Projekts im Speicher halten.
// Viele Testunits hatten dafür eigene, wortgleiche Routinen.

interface

uses
  System.Generics.Collections;

type
  /// <summary>Datei eines gedachten Projekts: Name und Inhalt.</summary>
  TTestFile = record
    Name: string;
    Text: string;
  end;

  TTestFiles = record
  public
    /// <summary>Setzt den Inhalt der Datei AName (Groß-/Kleinschreibung egal) oder hängt sie an.</summary>
    class procedure Put(var AFiles: TArray<TTestFile>; const AName, AText: string); static;
    /// <summary>Inhalt der Datei AName, '' wenn es sie nicht gibt.</summary>
    class function Text(const AFiles: TArray<TTestFile>; const AName: string): string; static;
  end;

  /// <summary>Unechte Platte: Ordner (klein geschrieben) → Dateien bzw. Unterordner.</summary>
  TTestDisk = record
  public
    /// <summary>Trägt AFileName unter seinem Ordner in AFiles ein.</summary>
    class procedure AddFile(const AFiles: TDictionary<string, TArray<string>>; const AFileName: string); static;
    /// <summary>Trägt AParent\AChild unter AParent in AFolders ein.</summary>
    class procedure AddFolder(const AFolders: TDictionary<string, TArray<string>>; const AParent, AChild: string);
      static;
  end;

  TTestData = record
  public
    /// <summary>Pfad von Tests\ARelative (Datei oder Ordner), gesucht ab dem Ordner des Testprogramms und dem
    /// aktuellen Ordner aufwärts; '' wenn es ihn nicht gibt.</summary>
    class function Path(const ARelative: string): string; static;
    /// <summary>Ordner Tests\Referenzprojekt, '' wenn es ihn nicht gibt.</summary>
    class function ReferenceFolder: string; static;
    /// <summary>Inhalt (UTF-8) von Tests\Data\AFolder\AName; Ausnahme, wenn die Datei fehlt.</summary>
    class function Fixture(const AFolder, AName: string): string; static;
    /// <summary>
    ///   Erfundener Projektordner AName für Pfadtests: C:\Projekte\AName unter Windows, sonst /projekte/aname.
    /// </summary>
    class function ProjectRoot(const AName: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils;

{ TTestFiles }

class procedure TTestFiles.Put(var AFiles: TArray<TTestFile>; const AName, AText: string);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AFiles) do
  begin
    if SameText(AFiles[mIndex].Name, AName) then
    begin
      AFiles[mIndex].Text := AText;
      Exit;
    end;
  end;
  SetLength(AFiles, Length(AFiles) + 1);
  AFiles[High(AFiles)].Name := AName;
  AFiles[High(AFiles)].Text := AText;
end;

class function TTestFiles.Text(const AFiles: TArray<TTestFile>; const AName: string): string;
var
  mEntry: TTestFile;
begin
  Result := '';
  for mEntry in AFiles do
  begin
    if SameText(mEntry.Name, AName) then
    begin
      Result := mEntry.Text;
    end;
  end;
end;

{ TTestDisk }

class procedure TTestDisk.AddFile(const AFiles: TDictionary<string, TArray<string>>; const AFileName: string);
var
  mFolder: string;
  mItems: TArray<string>;
begin
  mFolder := Copy(AFileName, 1, LastDelimiter('\', AFileName) - 1);
  if not AFiles.TryGetValue(LowerCase(mFolder), mItems) then
  begin
    mItems := nil;
  end;
  AFiles.AddOrSetValue(LowerCase(mFolder), mItems + [AFileName]);
end;

class procedure TTestDisk.AddFolder(const AFolders: TDictionary<string, TArray<string>>; const AParent,
  AChild: string);
var
  mItems: TArray<string>;
begin
  if not AFolders.TryGetValue(LowerCase(AParent), mItems) then
  begin
    mItems := nil;
  end;
  AFolders.AddOrSetValue(LowerCase(AParent), mItems + [AParent + '\' + AChild]);
end;

{ TTestData }

class function TTestData.Path(const ARelative: string): string;
var
  mStart, mDirectory: string;
begin
  for mStart in TArray<string>.Create(ExtractFileDir(ParamStr(0)), GetCurrentDir) do
  begin
    mDirectory := mStart;
    while mDirectory <> '' do
    begin
      Result := TPath.Combine(mDirectory, TPath.Combine('Tests', ARelative));
      if TFile.Exists(Result) or TDirectory.Exists(Result) then
      begin
        Exit;
      end;
      if ExtractFileDir(mDirectory) = mDirectory then
      begin
        Break;
      end;
      mDirectory := ExtractFileDir(mDirectory);
    end;
  end;
  Result := '';
end;

class function TTestData.ReferenceFolder: string;
begin
  Result := Path('Referenzprojekt');
end;

class function TTestData.Fixture(const AFolder, AName: string): string;
var
  mFileName: string;
begin
  mFileName := Path(TPath.Combine('Data', TPath.Combine(AFolder, AName)));
  if mFileName = '' then
  begin
    raise Exception.Create('Tests\Data\' + AFolder + '\' + AName + ' nicht gefunden');
  end;
  Result := TFile.ReadAllText(mFileName, TEncoding.UTF8);
end;

class function TTestData.ProjectRoot(const AName: string): string;
begin
  if PathDelim = '\' then
  begin
    Result := 'C:\Projekte\' + AName;
  end
  else
  begin
    Result := '/projekte/' + LowerCase(AName);
  end;
end;

end.
