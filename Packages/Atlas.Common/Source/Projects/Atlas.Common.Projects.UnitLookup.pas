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
//      System.SysUtils); ein Unit-Alias (WinTypes → Winapi.Windows,
//      TUnitAliases) wird ebenso gesucht
//   3a. Units, die ein anderes Projekt der Projektgruppe in einen dieser Ordner
//      übersetzt (DCC_DcuOutput): Die Gruppe baut es vorher, auch wenn die .dcu
//      für Plattform oder Konfiguration noch fehlt
//   4. bei Packages die Units der requires-Packages (.dpk bzw. .dcp), auch über
//      deren requires: dcc lädt mit Atlas.Common.dcp auch das davon verlangte
//      Atlas.Text.dcp, dessen Units damit ebenso sichtbar sind
// requires (FindPackage): ein Projekt der Projektgruppe gleichen Namens gilt
// als vorhanden, die Gruppe baut es vor diesem
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
  Atlas.Common.Projects.Contract.UnitLookup,
  Atlas.Common.Projects.UnitAliases;

type
  TUnitLookup = class(TInterfacedObject, IUnitLookup)
  private const
    /// <summary>So tief sucht FolderOutsidePaths unter dem Projektordner.</summary>
    cMaxFolderDepth = 4;
  private
    FSetup: TUnitLookupSetup;
    // Unit-Aliase des Projekts samt Vorgaben von Delphi; nach dem Konstruktor nur gelesen.
    FAliases: TArray<TUnitAlias>;
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
    /// <summary>Ist APackage ein Projekt der Gruppe (requires eines Packages derselben Projektgruppe)?</summary>
    function PackageInGroup(const APackage: string): Boolean;
    function InFolderAny(const AFolder: string; const ANames: TArray<string>): Boolean;
    /// <summary>Gibt es die Datei neben AFromFile oder in einem der Ordner für FindFile?</summary>
    function ExistsInFileFolders(const AFileName, AFromFile: string): Boolean;
  public
    constructor Create(const ASetup: TUnitLookupSetup);
    destructor Destroy; override;
    function Find(const AUnitName, AInPath, AFromFile: string; ASources: TUnitSources): TUnitAnswer;
    function FindPackage(const APackage: string): TUnitAnswer;
    function FindFile(const AFileName, AFromFile: string): TUnitAnswer;
    function KnownUnits(ASources: TUnitSources): TArray<string>;
    function FolderOutsidePaths(const AUnitName: string): string;
    function ReadProject(out AFileName, AText: string): Boolean;
    /// <summary>Ordner, die der Compiler durchsucht (ohne den der verwendenden Datei).</summary>
    property ProjectFolders: TArray<string> read FProjectFolders;
  end;

implementation

uses
  Atlas.Common.Projects.Contract,
  System.StrUtils,
  Atlas.Common.Projects.Paths,
  Atlas.Text.Arrays,
  Atlas.Text.Names;

/// <summary>Ordner als Vergleichsschlüssel: "\" als Trenner, ohne Trenner am Ende, klein.</summary>

function SameFolder(const A, B: string): Boolean;
begin
  Result := TTextNames.FolderKey(A) = TTextNames.FolderKey(B);
end;

function HasMacro(const APath: string): Boolean;
begin
  Result := Pos('$(', APath) > 0;
end;

/// <summary>Ordner aus DCC_IncludePath und DCC_ResourcePath, absolut (#1379).</summary>
function FileSearchPaths(const AProject: TProjectInfo): TArray<string>;
var
  mPair: TPair<string, string>;
  mPath: string;
begin
  Result := nil;
  for mPair in AProject.Properties do
  begin
    if SameText(mPair.Key, 'DCC_IncludePath') or SameText(mPair.Key, 'DCC_ResourcePath') then
    begin
      for mPath in TProjectPaths.SplitList(mPair.Value) do
      begin
        if (AProject.FileName <> '') and not TProjectPaths.IsAbsolute(mPath) and not HasMacro(mPath) then
        begin
          Result := Result + [TProjectPaths.Combine(TProjectPaths.DirectoryOf(AProject.FileName), mPath)];
        end
        else
        begin
          Result := Result + [mPath];
        end;
      end;
    end;
  end;
end;

{ TUnitLookup }

/// <summary>Ordner, die der Compiler durchsucht: Projektordner, Suchpfade, DCU-Ausgabe und Bibliothekspfade.
/// </summary>
function CompilerFolders(const ASetup: TUnitLookupSetup): TArray<string>;
var
  mFolder: string;
begin
  Result := nil;
  if ASetup.Project.FileName <> '' then
  begin
    Result := Result + [TProjectPaths.DirectoryOf(ASetup.Project.FileName)];
  end;
  Result := Result + ASetup.Project.SearchPaths;
  mFolder := TProjectPaths.DcuOutputOf(ASetup.Project);
  if mFolder <> '' then
  begin
    Result := Result + [mFolder];
  end;
  Result := Result + ASetup.LibraryPaths;
end;

function AnyMacro(const AFolders: TArray<string>): Boolean;
var
  mFolder: string;
begin
  Result := False;
  for mFolder in AFolders do
  begin
    if HasMacro(mFolder) then
    begin
      Exit(True);
    end;
  end;
end;

function ContainsFolder(const AFolders: TArray<string>; const AFolder: string): Boolean;
var
  mFolder: string;
begin
  Result := False;
  for mFolder in AFolders do
  begin
    if SameFolder(mFolder, AFolder) then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Trägt die Units (klein) der Projekte aus AOutputs in AUnits ein, die in einen der Ordner AFolders
/// übersetzen.</summary>
procedure AddGroupUnits(AUnits: TDictionary<string, Boolean>; const AOutputs: TArray<TUnitLookupGroupOutput>;
  const AFolders: TArray<string>);
var
  mOutput: TUnitLookupGroupOutput;
  mName: string;
begin
  for mOutput in AOutputs do
  begin
    if (mOutput.DcuFolder = '') or not ContainsFolder(AFolders, mOutput.DcuFolder) then
    begin
      Continue;
    end;
    for mName in mOutput.Units do
    begin
      AUnits.AddOrSetValue(LowerCase(mName), True);
    end;
  end;
end;

{ TUnitLookup }

constructor TUnitLookup.Create(const ASetup: TUnitLookupSetup);
var
  mUnit: TProjectUnit;
  mFileFolders: TArray<string>;
begin
  inherited Create;
  FSetup := ASetup;
  FAliases := TUnitAliases.OfProject(ASetup.Project);
  FLock := TObject.Create;
  FListings := TObjectDictionary<string, TDictionary<string, string>>.Create([doOwnsValues]);
  // Einmal je Projekt statt je uses-Eintrag und Namespace über alle Units (#1342).
  FProjectUnits := TDictionary<string, Boolean>.Create;
  FFolderAnswers := TDictionary<string, Boolean>.Create;
  FGroupUnits := TDictionary<string, Boolean>.Create;
  FLateUnits := TDictionary<string, Boolean>.Create;
  for mUnit in ASetup.Project.Units do
  begin
    FProjectUnits.AddOrSetValue(LowerCase(mUnit.Name), True);
  end;
  FProjectFolders := CompilerFolders(ASetup);
  AddGroupUnits(FGroupUnits, ASetup.GroupOutputs, FProjectFolders);
  // dcc sucht Include- und Ressourcendateien zusätzlich in -I und -R (#1379).
  mFileFolders := FileSearchPaths(ASetup.Project);
  FFileFolders := FProjectFolders + mFileFolders;
  // Ein Ordner mit offenem Makro kann jede Unit enthalten.
  FUncertain := AnyMacro(FProjectFolders) or AnyMacro(mFileFolders);
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
    begin
      Exit;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
  Result := False;
  for mFolder in FProjectFolders do
  begin
    for mName in ANames do
    begin
      if InFolder(mFolder, mName) then
      begin
        Result := True;
        Break;
      end;
    end;
    if Result then
    begin
      Break;
    end;
  end;
  TMonitor.Enter(FLock);
  try
    FFolderAnswers.AddOrSetValue(mKey, Result);
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TUnitLookup.Listing(const AFolder: string): TDictionary<string, string>;
var
  mKey, mFileName, mExtension: string;
begin
  mKey := TTextNames.FolderKey(AFolder);
  TMonitor.Enter(FLock);
  try
    if FListings.TryGetValue(mKey, Result) then
    begin
      Exit;
    end;
    Result := TDictionary<string, string>.Create;
    FListings.Add(mKey, Result);
    if Assigned(FSetup.ListFiles) and not HasMacro(AFolder) then
    begin
      for mFileName in FSetup.ListFiles(AFolder) do
      begin
        mExtension := LowerCase(TProjectPaths.Extension(mFileName));
        if (mExtension = '.pas') or (mExtension = '.dcu') then
        begin
          Result.AddOrSetValue(LowerCase(TProjectPaths.BaseName(mFileName)), TProjectPaths.BaseName(mFileName));
        end;
      end;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TUnitLookup.InFolder(const AFolder, AName: string): Boolean;
var
  mNames: TDictionary<string, string>;
begin
  mNames := Listing(AFolder);
  TMonitor.Enter(FLock);
  try
    Result := mNames.ContainsKey(LowerCase(AName));
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TUnitLookup.Candidates(const AUnitName: string): TArray<string>;
var
  mNamespace, mTarget: string;
begin
  Result := [AUnitName];
  for mNamespace in FSetup.Project.Namespaces do
  begin
    Result := Result + [mNamespace + '.' + AUnitName];
  end;
  // dcc ersetzt einen Alias durch seine Unit und sucht diese wie jede andere (WinTypes → Winapi.Windows).
  if TUnitAliases.Target(FAliases, AUnitName, mTarget) then
  begin
    Result := Result + [mTarget];
    for mNamespace in FSetup.Project.Namespaces do
    begin
      Result := Result + [mNamespace + '.' + mTarget];
    end;
  end;
end;

function ContainsAnyName(AKeys: TDictionary<string, Boolean>; const ANames: TArray<string>): Boolean;
var
  mName: string;
begin
  Result := False;
  for mName in ANames do
  begin
    if AKeys.ContainsKey(LowerCase(mName)) then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Hängt AName an AList, wenn er noch nicht in ASeen steht.</summary>
procedure AddUnseen(AList: TList<string>; ASeen: TDictionary<string, Boolean>; const AName: string);
begin
  if not ASeen.ContainsKey(LowerCase(AName)) then
  begin
    ASeen.Add(LowerCase(AName), True);
    AList.Add(AName);
  end;
end;

/// <summary>Liefert ein requires-Package die Unit (einer der Namen ANames), auch über die Packages, die es selbst
/// verlangt? Eine unbekannte Antwort setzt AUnsure.</summary>
function ProvidedByPackages(const ASetup: TUnitLookupSetup; const ANames: TArray<string>;
  var AUnsure: Boolean): Boolean;
var
  mPackages: TList<string>;
  mSeen: TDictionary<string, Boolean>;
  mPackage, mName: string;
  mPosition: Integer;
begin
  Result := False;
  mPackages := TList<string>.Create;
  mSeen := TDictionary<string, Boolean>.Create;
  try
    for mPackage in ASetup.RequiredPackages do
    begin
      AddUnseen(mPackages, mSeen, mPackage);
    end;
    mPosition := 0;
    while not Result and (mPosition < mPackages.Count) do
    begin
      mPackage := mPackages[mPosition];
      Inc(mPosition);
      for mName in ANames do
      begin
        case ASetup.PackageProvides(mPackage, mName) of
          TPackageAnswer.Yes:
            Result := True;
          TPackageAnswer.Unknown:
            AUnsure := True;
        end;
      end;
      if not Result and Assigned(ASetup.PackageRequires) then
      begin
        for mName in ASetup.PackageRequires(mPackage) do
        begin
          AddUnseen(mPackages, mSeen, mName);
        end;
      end;
    end;
  finally
    mSeen.Free;
    mPackages.Free;
  end;
end;

function TUnitLookup.FindInProject(const AUnitName, AFromFile: string; out AUnsure: Boolean): Boolean;
var
  mNames: TArray<string>;
begin
  AUnsure := False;
  mNames := Candidates(AUnitName);
  // Packages: Units der requires-Packages, auch ohne .dcu im Pfad, und die der Packages, die diese verlangen.
  Result := ContainsAnyName(FProjectUnits, mNames) or
    ((AFromFile <> '') and InFolderAny(TProjectPaths.DirectoryOf(AFromFile), mNames)) or
    InProjectFolders(AUnitName, mNames) or BuiltByGroup(mNames) or
    (Assigned(FSetup.PackageProvides) and ProvidedByPackages(FSetup, mNames, AUnsure));
  if not Result and (Length(FSetup.RequiredPackages) > 0) and not Assigned(FSetup.PackageProvides) then
  begin
    AUnsure := True;
  end;
end;

function TUnitLookup.FindInAtlas(const AUnitName: string): Boolean;
var
  mName, mFolder: string;
begin
  Result := True;
  for mName in Candidates(AUnitName) do
  begin
    if Assigned(FSetup.IndexKnows) and FSetup.IndexKnows(mName) then
    begin
      Exit;
    end;
    for mFolder in FSetup.BrowsingPaths do
    begin
      if InFolder(mFolder, mName) then
      begin
        Exit;
      end;
    end;
  end;
  Result := False;
end;

function TUnitLookup.BuiltByGroup(const ANames: TArray<string>): Boolean;
var
  mOutputs: TArray<TUnitLookupGroupOutput>;
begin
  if ContainsAnyName(FGroupUnits, ANames) or not Assigned(FSetup.GroupOutputsOf) then
  begin
    Exit(ContainsAnyName(FGroupUnits, ANames));
  end;
  mOutputs := FSetup.GroupOutputsOf();
  TMonitor.Enter(FLock);
  try
    // Dieselbe Liste (der Rückruf merkt sie sich): das Wörterbuch gilt weiter.
    if Pointer(mOutputs) <> Pointer(FLateOutputs) then
    begin
      FLateOutputs := mOutputs;
      FLateUnits.Clear;
      AddGroupUnits(FLateUnits, mOutputs, FProjectFolders);
    end;
    Result := ContainsAnyName(FLateUnits, ANames);
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TUnitLookup.PackageInGroup(const APackage: string): Boolean;
var
  mOutputs: TArray<TUnitLookupGroupOutput>;
  mOutput: TUnitLookupGroupOutput;
begin
  mOutputs := FSetup.GroupOutputs;
  if Assigned(FSetup.GroupOutputsOf) then
  begin
    mOutputs := mOutputs + FSetup.GroupOutputsOf();
  end;
  for mOutput in mOutputs do
  begin
    if (mOutput.ProjectName <> '') and SameText(mOutput.ProjectName, APackage) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Gibt es die Datei APath? Unbekannt ohne FileExists oder bei relativem Pfad.</summary>
function FileAnswer(const ASetup: TUnitLookupSetup; const APath: string): TUnitAnswer;
begin
  if not Assigned(ASetup.FileExists) or not TProjectPaths.IsAbsolute(APath) then
  begin
    Result := TUnitAnswer.Unknown;
  end
  else if ASetup.FileExists(TProjectPaths.Normalize(APath)) then
  begin
    Result := TUnitAnswer.Found;
  end
  else
  begin
    Result := TUnitAnswer.Missing;
  end;
end;

/// <summary>APath relativ zum Ordner von AFromFile, wenn er nicht absolut ist.</summary>
function BesideFile(const APath, AFromFile: string): string;
begin
  Result := APath;
  if not TProjectPaths.IsAbsolute(Result) and (AFromFile <> '') then
  begin
    Result := TProjectPaths.Combine(TProjectPaths.DirectoryOf(AFromFile), Result);
  end;
end;

function TUnitLookup.InFolderAny(const AFolder: string; const ANames: TArray<string>): Boolean;
var
  mName: string;
begin
  Result := False;
  for mName in ANames do
  begin
    if InFolder(AFolder, mName) then
    begin
      Exit(True);
    end;
  end;
end;

function TUnitLookup.ExistsInFileFolders(const AFileName, AFromFile: string): Boolean;
var
  mFolder: string;
begin
  Result := (AFromFile <> '') and FSetup.FileExists(TProjectPaths.Normalize(
    TProjectPaths.Combine(TProjectPaths.DirectoryOf(AFromFile), AFileName)));
  for mFolder in FFileFolders do
  begin
    if Result then
    begin
      Break;
    end;
    Result := not HasMacro(mFolder) and
      FSetup.FileExists(TProjectPaths.Normalize(TProjectPaths.Combine(mFolder, AFileName)));
  end;
end;

function TUnitLookup.Find(const AUnitName, AInPath, AFromFile: string; ASources: TUnitSources): TUnitAnswer;
var
  mUnsure: Boolean;
begin
  if AInPath <> '' then
  begin
    // "in 'Pfad'": nur diese Datei, relativ zur verwendenden Datei. Offene Makros kennt dcc hier nicht.
    Exit(FileAnswer(FSetup, BesideFile(AInPath, AFromFile)));
  end;
  mUnsure := False;
  if ((TUnitSource.Project in ASources) and FindInProject(AUnitName, AFromFile, mUnsure)) or
    ((TUnitSource.Atlas in ASources) and FindInAtlas(AUnitName)) then
  begin
    Result := TUnitAnswer.Found;
  end
  else if mUnsure or FUncertain or not FSetup.LibraryKnown or not Assigned(FSetup.ListFiles) then
  begin
    Result := TUnitAnswer.Unknown;
  end
  else if (ASources = [TUnitSource.Atlas]) and not Assigned(FSetup.IndexKnows) then
  begin
    // Nur Atlas ohne Index: Die Units der Installation stehen dann nirgends.
    Result := TUnitAnswer.Unknown;
  end
  else
  begin
    Result := TUnitAnswer.Missing;
  end;
end;

function TUnitLookup.FindPackage(const APackage: string): TUnitAnswer;
begin
  // Ein Package derselben Projektgruppe entsteht beim Bauen der Gruppe, auch wenn seine .dcp noch fehlt.
  if PackageInGroup(APackage) then
  begin
    Exit(TUnitAnswer.Found);
  end;
  if not Assigned(FSetup.PackageExists) or not FSetup.LibraryKnown or FUncertain then
  begin
    Exit(TUnitAnswer.Unknown);
  end;
  if FSetup.PackageExists(APackage) then
  begin
    Exit(TUnitAnswer.Found);
  end;
  Result := TUnitAnswer.Missing;
end;

function TUnitLookup.FindFile(const AFileName, AFromFile: string): TUnitAnswer;
begin
  if not Assigned(FSetup.FileExists) or (AFileName = '') then
  begin
    Result := TUnitAnswer.Unknown;
  end
  else if TProjectPaths.IsAbsolute(AFileName) then
  begin
    Result := FileAnswer(FSetup, AFileName);
  end
  else if ExistsInFileFolders(AFileName, AFromFile) then
  begin
    Result := TUnitAnswer.Found;
  end
  else if FUncertain or not FSetup.LibraryKnown then
  begin
    Result := TUnitAnswer.Unknown;
  end
  else
  begin
    Result := TUnitAnswer.Missing;
  end;
end;

function TUnitLookup.KnownUnits(ASources: TUnitSources): TArray<string>;
var
  mSeen: TDictionary<string, Boolean>;
  mFolders: TArray<string>;
  mFolder, mName: string;
  mProjectUnit: TProjectUnit;
begin
  Result := nil;
  mSeen := TDictionary<string, Boolean>.Create;
  try
    mFolders := nil;
    if TUnitSource.Project in ASources then
    begin
      for mProjectUnit in FSetup.Project.Units do
      begin
        TTextArrays.AddUniqueText(Result, mSeen, mProjectUnit.Name);
      end;
      mFolders := FProjectFolders;
    end;
    if TUnitSource.Atlas in ASources then
    begin
      mFolders := mFolders + FSetup.BrowsingPaths;
      if Assigned(FSetup.IndexUnits) then
      begin
        for mName in FSetup.IndexUnits() do
        begin
          TTextArrays.AddUniqueText(Result, mSeen, mName);
        end;
      end;
    end;
    for mFolder in mFolders do
    begin
      for mName in Listing(mFolder).Values do
      begin
        TTextArrays.AddUniqueText(Result, mSeen, mName);
      end;
    end;
  finally
    mSeen.Free;
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

/// <summary>AFolder relativ zu ARoot, ohne Trenner am Anfang und Ende.</summary>
function RelativeFolder(const ARoot, AFolder: string): string;
begin
  Result := Copy(AFolder, Length(ARoot) + 1, MaxInt);
  while (Result <> '') and CharInSet(Result[1], ['\', '/']) do
  begin
    Delete(Result, 1, 1);
  end;
  while (Result <> '') and CharInSet(Result[Length(Result)], ['\', '/']) do
  begin
    Delete(Result, Length(Result), 1);
  end;
end;

function TUnitLookup.FolderOutsidePaths(const AUnitName: string): string;
var
  mRoot, mFolder: string;
  mQueue: TList<TQueuedFolder>;
  mItem: TQueuedFolder;
  mPosition: Integer;
begin
  Result := '';
  if (FSetup.Project.FileName = '') or not Assigned(FSetup.ListFolders) then
  begin
    Exit;
  end;
  mRoot := TProjectPaths.DirectoryOf(FSetup.Project.FileName);
  mQueue := TList<TQueuedFolder>.Create;
  try
    mQueue.Add(Queued(mRoot, 0));
    mPosition := 0;
    while mPosition < mQueue.Count do
    begin
      mItem := mQueue[mPosition];
      Inc(mPosition);
      if (mItem.Depth > 0) and not ContainsFolder(FProjectFolders, mItem.Folder) and
        InFolder(mItem.Folder, AUnitName) then
      begin
        // Relativ zur .dproj, mit dem Trenner der Pfade.
        Exit(RelativeFolder(mRoot, mItem.Folder));
      end;
      if mItem.Depth >= cMaxFolderDepth then
      begin
        Continue;
      end;
      for mFolder in FSetup.ListFolders(mItem.Folder) do
      begin
        mQueue.Add(Queued(mFolder, mItem.Depth + 1));
      end;
    end;
  finally
    mQueue.Free;
  end;
end;

function TUnitLookup.ReadProject(out AFileName, AText: string): Boolean;
begin
  AFileName := FSetup.Project.FileName;
  AText := '';
  Result := (AFileName <> '') and Assigned(FSetup.ReadText) and FSetup.ReadText(AFileName, AText);
end;

end.
