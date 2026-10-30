unit Atlas.Common.Projects.UnitLookup;

// Unit-Suche wie beim Compiler für uses-unit-not-found (#1016). Anders als
// TUnitResolver, der Quelltexte für den Index sucht, zählt hier auch die
// übersetzte Unit (.dcu): Viele Units der Installation und fremder Bibliotheken
// gibt es nur so.
//
// Quelle Project (Vorgabe, so sucht dcc):
//   1. mit "in 'Pfad'" nur diese Datei, relativ zur verwendenden Datei (F1026)
//   2. Units des Projekts (DCCReference); System und SysInit werden wie jede
//      Unit gesucht: Fehlt System, fehlt der Bibliothekspfad (F1027)
//   3. Ordner der verwendenden Datei, Projektordner, Suchpfade der .dproj,
//      DCU-Ausgabeordner, Bibliothekspfade der Installation; je Ordner Name.pas
//      oder Name.dcu, auch mit jedem Unit-Namespace davor (SysUtils →
//      System.SysUtils)
//   3a. Units, die ein anderes Projekt der Projektgruppe in einen dieser Ordner
//      übersetzt (DCC_DcuOutput): Die Gruppe baut es vorher, auch wenn die .dcu
//      für Plattform oder Konfiguration noch fehlt
//   4. bei Packages die Units der requires-Packages (.dpk bzw. .dcp), auch über
//      deren requires: dcc lädt mit Atlas.Common.dcp auch das davon verlangte
//      Atlas.Text.dcp, dessen Units damit ebenso sichtbar sind
// Quelle Atlas: Units im Index und in den Quellpfaden (Browsing Path).
//
// Dateien aus {$I} und {$R} (FindFile, #1379): Ordner der einbindenden Datei,
// dann die Ordner aus 3. samt DCC_IncludePath und DCC_ResourcePath.
//
// Sicher fehlend (Missing) ist eine Unit nur, wenn die Bibliothekspfade der
// Installation bekannt sind, kein Suchpfad ein offenes Makro "$(…)" enthält und
// kein requires-Package unbekannt ist; sonst Unknown, die Regel schweigt.
// Dateizugriffe kommen von außen (Tests ohne Platte, im Server geteilte
// Ordnerlisten). Die Klasse ist threadsicher.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Rules.Contract;

type
  /// <summary>Liest eine Textdatei; False, wenn sie fehlt.</summary>
  TUnitLookupReadText = reference to function(const AFileName: string; out AText: string): Boolean;

  /// <summary>Anderes Projekt der Gruppe: Ordner, in den es übersetzt, und seine Units.</summary>
  TUnitLookupGroupOutput = record
    /// <summary>DCU-Ausgabeordner, absolut, mit eingesetzter Plattform und Konfiguration.</summary>
    DcuFolder: string;
    Units: TArray<string>;
  end;

  /// <summary>Was TUnitLookup über Projekt, Installation und Dateisystem wissen muss.</summary>
  TUnitLookupSetup = record
    Project: TProjectInfo;
    /// <summary>Bibliothekspfade der Installation (Library Path) in Suchreihenfolge, absolut.</summary>
    LibraryPaths: TArray<string>;
    /// <summary>Installation bekannt: Ohne gilt keine Unit als sicher fehlend.</summary>
    LibraryKnown: Boolean;
    /// <summary>Quellpfade der Installation (Browsing Path) für die Quelle Atlas.</summary>
    BrowsingPaths: TArray<string>;
    /// <summary>Packages aus requires der Hauptdatei (.dpk); leer bei Programmen.</summary>
    RequiredPackages: TArray<string>;
    /// <summary>Dateien eines Ordners (vollständige Pfade, mindestens .pas und .dcu); leer, wenn es ihn nicht gibt.
    /// </summary>
    ListFiles: TFunc<string, TArray<string>>;
    /// <summary>Unterordner eines Ordners (vollständige Pfade); nil = keine Suche außerhalb der Suchpfade.</summary>
    ListFolders: TFunc<string, TArray<string>>;
    FileExists: TFunc<string, Boolean>;
    /// <summary>Text einer Datei (.dproj); nil = keine Korrektur am Suchpfad.</summary>
    ReadText: TUnitLookupReadText;
    /// <summary>Liefert Package APackage die Unit? nil = keine requires-Prüfung.</summary>
    PackageProvides: TRulePackageProvides;
    /// <summary>requires eines Packages (aus der .dpk); leer ohne Quelle. nil = nur die direkten Packages.</summary>
    PackageRequires: TFunc<string, TArray<string>>;
    /// <summary>Gibt es das Package (.dpk oder .dcp)? nil = unbekannt.</summary>
    PackageExists: TFunc<string, Boolean>;
    /// <summary>Steht die Unit im Index (Quelle Atlas)? nil = Index unbekannt.</summary>
    IndexKnows: TFunc<string, Boolean>;
    /// <summary>Namen der Units im Index für Vorschläge; nil = keine.</summary>
    IndexUnits: TFunc<TArray<string>>;
    /// <summary>Die anderen Projekte der Projektgruppe (3a).</summary>
    GroupOutputs: TArray<TUnitLookupGroupOutput>;
    /// <summary>Wie GroupOutputs, aber bei jeder Suche neu gefragt: Die IDE meldet die Projekte der Gruppe einzeln
    /// und nach diesem an. nil = nur GroupOutputs.</summary>
    GroupOutputsOf: TFunc<TArray<TUnitLookupGroupOutput>>;
  end;

  TUnitLookup = class(TInterfacedObject, IRuleUnitLookup)
  private const
    /// <summary>So tief sucht FolderOutsidePaths unter dem Projektordner.</summary>
    MaxFolderDepth = 4;
  private
    FSetup: TUnitLookupSetup;
    FProjectFolders: TArray<string>;
    FUncertain: Boolean;
    // Ordner für FindFile (#1379): FProjectFolders samt Include- und Ressourcenpfaden; nach dem Konstruktor nur
    // gelesen.
    FFileFolders: TArray<string>;
    FLock: TObject;
    // Ordner (klein) -> Unit-Namen (klein) -> Schreibweise. Unter FLock.
    FListings: TObjectDictionary<string, TDictionary<string, string>>;
    // Namen der Projekt-Units (klein); nach dem Konstruktor nur gelesen.
    FProjectUnits: TDictionary<string, Boolean>;
    // Unit-Name (klein) -> in einem der Projektordner gefunden. Unter FLock.
    FFolderAnswers: TDictionary<string, Boolean>;
    // Units (klein), die ein Projekt der Gruppe in einen der Projektordner übersetzt; nach dem Konstruktor nur gelesen.
    FGroupUnits: TDictionary<string, Boolean>;
    // Wie FGroupUnits für GroupOutputsOf: neu gebaut, wenn der Rückruf eine andere Liste liefert. Unter FLock.
    FLateOutputs: TArray<TUnitLookupGroupOutput>;
    FLateUnits: TDictionary<string, Boolean>;
    function InProjectFolders(const AUnitName: string; const ANames: TArray<string>): Boolean;
    function Listing(const AFolder: string): TDictionary<string, string>;
    function InFolder(const AFolder, AName: string): Boolean;
    function Candidates(const AUnitName: string): TArray<string>;
    function FindInProject(const AUnitName, AFromFile: string; out AUnsure: Boolean): Boolean;
    function FindInAtlas(const AUnitName: string): Boolean;
    function BuiltByGroup(const ANames: TArray<string>): Boolean;
  public
    constructor Create(const ASetup: TUnitLookupSetup);
    destructor Destroy; override;
    function Find(const AUnitName, AInPath, AFromFile: string; ASources: TRuleUnitSources): TRuleUnitAnswer;
    function FindPackage(const APackage: string): TRuleUnitAnswer;
    function FindFile(const AFileName, AFromFile: string): TRuleUnitAnswer;
    function KnownUnits(ASources: TRuleUnitSources): TArray<string>;
    function FolderOutsidePaths(const AUnitName: string): string;
    function ReadProject(out AFileName, AText: string): Boolean;
    /// <summary>DCU-Ausgabeordner (DCC_DcuOutput) mit eingesetzter Plattform und Konfiguration; '' ohne.</summary>
    class function DcuOutputOf(const AProject: TProjectInfo): string; static;
    /// <summary>Ordner, die der Compiler durchsucht (ohne den der verwendenden Datei).</summary>
    property ProjectFolders: TArray<string> read FProjectFolders;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Common.Projects.Paths;

/// <summary>Ordner als Vergleichsschlüssel: "\" als Trenner, ohne Trenner am Ende, klein.</summary>
function FolderKey(const AFolder: string): string;
begin
  Result := LowerCase(StringReplace(AFolder, '/', '\', [rfReplaceAll]));
  while (Length(Result) > 1) and (Result[Length(Result)] = '\') do
    Delete(Result, Length(Result), 1);
end;

function SameFolder(const A, B: string): Boolean;
begin
  Result := FolderKey(A) = FolderKey(B);
end;

function HasMacro(const APath: string): Boolean;
begin
  Result := Pos('$(', APath) > 0;
end;

/// <summary>DCU-Ausgabeordner (DCC_DcuOutput) mit eingesetzter Plattform und Konfiguration; '' ohne.</summary>
function DcuOutput(const AProject: TProjectInfo): string;
var
  Pair: TPair<string, string>;
begin
  Result := '';
  for Pair in AProject.Properties do
    if SameText(Pair.Key, 'DCC_DcuOutput') then
      Result := Pair.Value;
  if Result = '' then
    Exit;
  Result := StringReplace(Result, '$(Platform)', AProject.Platform, [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '$(Config)', AProject.Config, [rfReplaceAll, rfIgnoreCase]);
  if (AProject.FileName <> '') and not TProjectPaths.IsAbsolute(Result) then
    Result := TProjectPaths.Combine(TProjectPaths.DirectoryOf(AProject.FileName), Result);
end;

/// <summary>Ordner aus DCC_IncludePath und DCC_ResourcePath, absolut (#1379).</summary>
function FileSearchPaths(const AProject: TProjectInfo): TArray<string>;
var
  mPair: TPair<string, string>;
  mPath: string;
begin
  Result := nil;
  for mPair in AProject.Properties do
    if SameText(mPair.Key, 'DCC_IncludePath') or SameText(mPair.Key, 'DCC_ResourcePath') then
      for mPath in TProjectPaths.SplitList(mPair.Value) do
        if (AProject.FileName <> '') and not TProjectPaths.IsAbsolute(mPath) and not HasMacro(mPath) then
          Result := Result + [TProjectPaths.Combine(TProjectPaths.DirectoryOf(AProject.FileName), mPath)]
        else
          Result := Result + [mPath];
end;

{ TUnitLookup }

constructor TUnitLookup.Create(const ASetup: TUnitLookupSetup);
var
  Folders: TList<string>;
  Folder, mName: string;
  mUnit: TProjectUnit;
  mOutput: TUnitLookupGroupOutput;
begin
  inherited Create;
  FSetup := ASetup;
  FLock := TObject.Create;
  FListings := TObjectDictionary<string, TDictionary<string, string>>.Create([doOwnsValues]);
  // Einmal je Projekt statt je uses-Eintrag und Namespace über alle Units (#1342).
  FProjectUnits := TDictionary<string, Boolean>.Create;
  FFolderAnswers := TDictionary<string, Boolean>.Create;
  FGroupUnits := TDictionary<string, Boolean>.Create;
  FLateUnits := TDictionary<string, Boolean>.Create;
  for mUnit in ASetup.Project.Units do
    FProjectUnits.AddOrSetValue(LowerCase(mUnit.Name), True);
  Folders := TList<string>.Create;
  try
    if ASetup.Project.FileName <> '' then
      Folders.Add(TProjectPaths.DirectoryOf(ASetup.Project.FileName));
    for Folder in ASetup.Project.SearchPaths do
      Folders.Add(Folder);
    Folder := DcuOutputOf(ASetup.Project);
    if Folder <> '' then
      Folders.Add(Folder);
    for Folder in ASetup.LibraryPaths do
      Folders.Add(Folder);
    // Ein Ordner mit offenem Makro kann jede Unit enthalten.
    for Folder in Folders do
      if HasMacro(Folder) then
        FUncertain := True;
    FProjectFolders := Folders.ToArray;
    for mOutput in ASetup.GroupOutputs do
      for Folder in FProjectFolders do
        if (mOutput.DcuFolder <> '') and SameFolder(Folder, mOutput.DcuFolder) then
        begin
          for mName in mOutput.Units do
            FGroupUnits.AddOrSetValue(LowerCase(mName), True);
          Break;
        end;
    // dcc sucht Include- und Ressourcendateien zusätzlich in -I und -R (#1379).
    FFileFolders := FProjectFolders;
    for Folder in FileSearchPaths(ASetup.Project) do
    begin
      FFileFolders := FFileFolders + [Folder];
      if HasMacro(Folder) then
        FUncertain := True;
    end;
  finally
    Folders.Free;
  end;
end;

destructor TUnitLookup.Destroy;
begin
  FLateUnits.Free;
  FGroupUnits.Free;
  FFolderAnswers.Free;
  FProjectUnits.Free;
  FListings.Free;
  FLock.Free;
  inherited;
end;

function TUnitLookup.Listing(const AFolder: string): TDictionary<string, string>;
var
  Key, FileName, Extension: string;
begin
  Key := FolderKey(AFolder);
  TMonitor.Enter(FLock);
  try
    if FListings.TryGetValue(Key, Result) then
      Exit;
    Result := TDictionary<string, string>.Create;
    FListings.Add(Key, Result);
    if Assigned(FSetup.ListFiles) and not HasMacro(AFolder) then
      for FileName in FSetup.ListFiles(AFolder) do
      begin
        Extension := LowerCase(TProjectPaths.Extension(FileName));
        if (Extension = '.pas') or (Extension = '.dcu') then
          Result.AddOrSetValue(LowerCase(TProjectPaths.BaseName(FileName)), TProjectPaths.BaseName(FileName));
      end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TUnitLookup.InFolder(const AFolder, AName: string): Boolean;
var
  Names: TDictionary<string, string>;
begin
  Names := Listing(AFolder);
  TMonitor.Enter(FLock);
  try
    Result := Names.ContainsKey(LowerCase(AName));
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TUnitLookup.Candidates(const AUnitName: string): TArray<string>;
var
  Namespace: string;
begin
  Result := [AUnitName];
  for Namespace in FSetup.Project.Namespaces do
    Result := Result + [Namespace + '.' + AUnitName];
end;

function TUnitLookup.InProjectFolders(const AUnitName: string; const ANames: TArray<string>): Boolean;
var
  mKey, mFolder, mName: string;
begin
  // Die Ordnerlisten ändern sich nach dem ersten Lesen nicht: die Antwort je Unit merken statt sie für jeden
  // uses-Eintrag über alle Ordner und Namespaces neu zu suchen (#1342).
  mKey := LowerCase(AUnitName);
  TMonitor.Enter(FLock);
  try
    if FFolderAnswers.TryGetValue(mKey, Result) then
      Exit;
  finally
    TMonitor.Exit(FLock);
  end;
  Result := False;
  for mFolder in FProjectFolders do
  begin
    for mName in ANames do
      if InFolder(mFolder, mName) then
      begin
        Result := True;
        Break;
      end;
    if Result then
      Break;
  end;
  TMonitor.Enter(FLock);
  try
    FFolderAnswers.AddOrSetValue(mKey, Result);
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TUnitLookup.FindInProject(const AUnitName, AFromFile: string; out AUnsure: Boolean): Boolean;
var
  Names: TArray<string>;
  Name, Package, mRequired: string;
  mPackages: TList<string>;
  mSeen: TDictionary<string, Boolean>;
  mPosition: Integer;
begin
  AUnsure := False;
  Result := True;
  Names := Candidates(AUnitName);
  for Name in Names do
    if FProjectUnits.ContainsKey(LowerCase(Name)) then
      Exit;
  if AFromFile <> '' then
    for Name in Names do
      if InFolder(TProjectPaths.DirectoryOf(AFromFile), Name) then
        Exit;
  if InProjectFolders(AUnitName, Names) then
    Exit;
  if BuiltByGroup(Names) then
    Exit;
  // Packages: Units der requires-Packages, auch ohne .dcu im Pfad, und die der Packages, die diese verlangen.
  if Assigned(FSetup.PackageProvides) then
  begin
    mPackages := TList<string>.Create;
    mSeen := TDictionary<string, Boolean>.Create;
    try
      for Package in FSetup.RequiredPackages do
        if not mSeen.ContainsKey(LowerCase(Package)) then
        begin
          mSeen.Add(LowerCase(Package), True);
          mPackages.Add(Package);
        end;
      mPosition := 0;
      while mPosition < mPackages.Count do
      begin
        Package := mPackages[mPosition];
        Inc(mPosition);
        for Name in Names do
          case FSetup.PackageProvides(Package, Name) of
            TRulePackageAnswer.Yes:
              Exit;
            TRulePackageAnswer.Unknown:
              AUnsure := True;
          end;
        if Assigned(FSetup.PackageRequires) then
          for mRequired in FSetup.PackageRequires(Package) do
            if not mSeen.ContainsKey(LowerCase(mRequired)) then
            begin
              mSeen.Add(LowerCase(mRequired), True);
              mPackages.Add(mRequired);
            end;
      end;
    finally
      mSeen.Free;
      mPackages.Free;
    end;
  end;
  if (Length(FSetup.RequiredPackages) > 0) and not Assigned(FSetup.PackageProvides) then
    AUnsure := True;
  Result := False;
end;

function TUnitLookup.BuiltByGroup(const ANames: TArray<string>): Boolean;
var
  mName, mUnit, mFolder: string;
  mOutputs: TArray<TUnitLookupGroupOutput>;
  mOutput: TUnitLookupGroupOutput;
begin
  Result := True;
  for mName in ANames do
    if FGroupUnits.ContainsKey(LowerCase(mName)) then
      Exit;
  if not Assigned(FSetup.GroupOutputsOf) then
    Exit(False);
  mOutputs := FSetup.GroupOutputsOf();
  TMonitor.Enter(FLock);
  try
    // Dieselbe Liste (der Rückruf merkt sie sich): das Wörterbuch gilt weiter.
    if Pointer(mOutputs) <> Pointer(FLateOutputs) then
    begin
      FLateOutputs := mOutputs;
      FLateUnits.Clear;
      for mOutput in mOutputs do
        for mFolder in FProjectFolders do
          if (mOutput.DcuFolder <> '') and SameFolder(mFolder, mOutput.DcuFolder) then
          begin
            for mUnit in mOutput.Units do
              FLateUnits.AddOrSetValue(LowerCase(mUnit), True);
            Break;
          end;
    end;
    for mName in ANames do
      if FLateUnits.ContainsKey(LowerCase(mName)) then
        Exit;
  finally
    TMonitor.Exit(FLock);
  end;
  Result := False;
end;

function TUnitLookup.FindInAtlas(const AUnitName: string): Boolean;
var
  Name, Folder: string;
begin
  Result := True;
  for Name in Candidates(AUnitName) do
  begin
    if Assigned(FSetup.IndexKnows) and FSetup.IndexKnows(Name) then
      Exit;
    for Folder in FSetup.BrowsingPaths do
      if InFolder(Folder, Name) then
        Exit;
  end;
  Result := False;
end;

function TUnitLookup.Find(const AUnitName, AInPath, AFromFile: string; ASources: TRuleUnitSources): TRuleUnitAnswer;
var
  Path: string;
  Unsure: Boolean;
begin
  if AInPath <> '' then
  begin
    // "in 'Pfad'": nur diese Datei, relativ zur verwendenden Datei. Offene Makros kennt dcc hier nicht.
    Path := AInPath;
    if not TProjectPaths.IsAbsolute(Path) and (AFromFile <> '') then
      Path := TProjectPaths.Combine(TProjectPaths.DirectoryOf(AFromFile), Path);
    if not Assigned(FSetup.FileExists) or not TProjectPaths.IsAbsolute(Path) then
      Exit(TRuleUnitAnswer.Unknown);
    if FSetup.FileExists(TProjectPaths.Normalize(Path)) then
      Exit(TRuleUnitAnswer.Found);
    Exit(TRuleUnitAnswer.Missing);
  end;
  Unsure := False;
  if (TRuleUnitSource.Project in ASources) and FindInProject(AUnitName, AFromFile, Unsure) then
    Exit(TRuleUnitAnswer.Found);
  if (TRuleUnitSource.Atlas in ASources) and FindInAtlas(AUnitName) then
    Exit(TRuleUnitAnswer.Found);
  if Unsure or FUncertain or not FSetup.LibraryKnown or not Assigned(FSetup.ListFiles) then
    Exit(TRuleUnitAnswer.Unknown);
  // Nur Atlas ohne Index: Die Units der Installation stehen dann nirgends.
  if (ASources = [TRuleUnitSource.Atlas]) and not Assigned(FSetup.IndexKnows) then
    Exit(TRuleUnitAnswer.Unknown);
  Result := TRuleUnitAnswer.Missing;
end;

function TUnitLookup.FindPackage(const APackage: string): TRuleUnitAnswer;
begin
  if not Assigned(FSetup.PackageExists) or not FSetup.LibraryKnown or FUncertain then
    Exit(TRuleUnitAnswer.Unknown);
  if FSetup.PackageExists(APackage) then
    Exit(TRuleUnitAnswer.Found);
  Result := TRuleUnitAnswer.Missing;
end;

function TUnitLookup.FindFile(const AFileName, AFromFile: string): TRuleUnitAnswer;
var
  mFolder: string;
begin
  if not Assigned(FSetup.FileExists) or (AFileName = '') then
    Exit(TRuleUnitAnswer.Unknown);
  if TProjectPaths.IsAbsolute(AFileName) then
  begin
    if FSetup.FileExists(TProjectPaths.Normalize(AFileName)) then
      Exit(TRuleUnitAnswer.Found);
    Exit(TRuleUnitAnswer.Missing);
  end;
  if (AFromFile <> '') and FSetup.FileExists(TProjectPaths.Normalize(
    TProjectPaths.Combine(TProjectPaths.DirectoryOf(AFromFile), AFileName))) then
    Exit(TRuleUnitAnswer.Found);
  for mFolder in FFileFolders do
    if not HasMacro(mFolder) and
      FSetup.FileExists(TProjectPaths.Normalize(TProjectPaths.Combine(mFolder, AFileName))) then
      Exit(TRuleUnitAnswer.Found);
  if FUncertain or not FSetup.LibraryKnown then
    Exit(TRuleUnitAnswer.Unknown);
  Result := TRuleUnitAnswer.Missing;
end;

function TUnitLookup.KnownUnits(ASources: TRuleUnitSources): TArray<string>;
var
  Seen: TDictionary<string, Boolean>;
  Folders: TArray<string>;
  Folder, Name: string;
  ProjectUnit: TProjectUnit;

  procedure Add(const AName: string);
  begin
    if (AName <> '') and not Seen.ContainsKey(LowerCase(AName)) then
    begin
      Seen.Add(LowerCase(AName), True);
      Result := Result + [AName];
    end;
  end;

begin
  Result := nil;
  Seen := TDictionary<string, Boolean>.Create;
  try
    Folders := nil;
    if TRuleUnitSource.Project in ASources then
    begin
      for ProjectUnit in FSetup.Project.Units do
        Add(ProjectUnit.Name);
      Folders := FProjectFolders;
    end;
    if TRuleUnitSource.Atlas in ASources then
    begin
      Folders := Folders + FSetup.BrowsingPaths;
      if Assigned(FSetup.IndexUnits) then
        for Name in FSetup.IndexUnits() do
          Add(Name);
    end;
    for Folder in Folders do
      for Name in Listing(Folder).Values do
        Add(Name);
  finally
    Seen.Free;
  end;
end;

type
  TQueuedFolder = record
    Folder: string;
    Depth: Integer;
  end;

function Queued(const AFolder: string; ADepth: Integer): TQueuedFolder;
begin
  Result.Folder := AFolder;
  Result.Depth := ADepth;
end;

function TUnitLookup.FolderOutsidePaths(const AUnitName: string): string;
var
  Root: string;
  Queue: TList<TQueuedFolder>;
  Item: TQueuedFolder;
  Folder, Searched: string;
  Known: Boolean;
  Position: Integer;
begin
  Result := '';
  if (FSetup.Project.FileName = '') or not Assigned(FSetup.ListFolders) then
    Exit;
  Root := TProjectPaths.DirectoryOf(FSetup.Project.FileName);
  Queue := TList<TQueuedFolder>.Create;
  try
    Queue.Add(Queued(Root, 0));
    Position := 0;
    while Position < Queue.Count do
    begin
      Item := Queue[Position];
      Inc(Position);
      Known := False;
      for Searched in FProjectFolders do
        if SameFolder(Searched, Item.Folder) then
          Known := True;
      if not Known and (Item.Depth > 0) and InFolder(Item.Folder, AUnitName) then
      begin
        // Relativ zur .dproj, mit dem Trenner der Pfade.
        Result := Copy(Item.Folder, Length(Root) + 1, MaxInt);
        while (Result <> '') and CharInSet(Result[1], ['\', '/']) do
          Delete(Result, 1, 1);
        while (Result <> '') and CharInSet(Result[Length(Result)], ['\', '/']) do
          Delete(Result, Length(Result), 1);
        Exit;
      end;
      if Item.Depth < MaxFolderDepth then
        for Folder in FSetup.ListFolders(Item.Folder) do
          Queue.Add(Queued(Folder, Item.Depth + 1));
    end;
  finally
    Queue.Free;
  end;
end;

class function TUnitLookup.DcuOutputOf(const AProject: TProjectInfo): string;
begin
  Result := DcuOutput(AProject);
end;

function TUnitLookup.ReadProject(out AFileName, AText: string): Boolean;
begin
  AFileName := FSetup.Project.FileName;
  AText := '';
  Result := (AFileName <> '') and Assigned(FSetup.ReadText) and FSetup.ReadText(AFileName, AText);
end;

end.
