unit Atlas.Core.Debug.OwnCode;

// Nur eigener Code beim Debuggen (#578), ohne VCL und Open Tools API.
//   - Eigener Code: Dateien unter den Projektordnern der Projektgruppe und
//     unter debug.ownCodeFolders; alles andere (RTL, VCL, Komponenten, Rahmen
//     ohne Quelltext) gilt als Bibliothek.
//   - Ort einer Exception: mit debug.justMyCode der erste eigene Rahmen des
//     Aufrufstapels (der ursprüngliche bleibt im Stapel sichtbar), sonst der
//     erste mit Quelltext (#517).
//   - Sprung: Steht der oberste Rahmen mit Quelltext nicht im eigenen Code,
//     springt Atlas zum ersten eigenen.
//   - Hineinspringen (F7): Landet der Schritt in Code ohne Quelltext, setzt
//     Atlas mit „Bis zur Rückkehr“ fort, höchstens MaxReturns-mal in Folge.
//   - Anzeige des Stapels: Bibliotheksrahmen abgeschwächt, zwei und mehr in
//     Folge als eine Zeile „… n Bibliotheksrahmen“, die sich aufklappen lässt.

interface

uses
  Atlas.Core.Debug.CallStack;

type
  {$SCOPEDENUMS ON}
  TAtlasDebugStackRowKind = (Frame, LibraryGroup);
  {$SCOPEDENUMS OFF}

  /// <summary>Zeile der Stapelanzeige: ein Rahmen oder mehrere zusammengefasste Bibliotheksrahmen.</summary>
  TAtlasDebugStackRow = record
    Kind: TAtlasDebugStackRowKind;
    /// <summary>Index des (ersten) Rahmens.</summary>
    First: Integer;
    /// <summary>Anzahl der Rahmen (1 bei Kind = Frame).</summary>
    Count: Integer;
    /// <summary>Abgeschwächt zeichnen (Bibliotheksrahmen bzw. Gruppe).</summary>
    Faded: Boolean;
  end;

  TAtlasDebugStackRows = TArray<TAtlasDebugStackRow>;

  TAtlasDebugOwnCode = record
  public const
    /// <summary>So oft setzt Atlas nach einem Hineinspringen höchstens „Bis zur Rückkehr“ fort.</summary>
    cMaxReturns = 16;
    /// <summary>Ab so vielen Bibliotheksrahmen in Folge fasst die Anzeige zusammen.</summary>
    cGroupFrom = 2;
  public
    Folders: TArray<string>;
    class function Create(const AFolders: TArray<string>): TAtlasDebugOwnCode; static;
    /// <summary>Ordnerliste aus debug.ownCodeFolders: durch „;“ oder Zeilen getrennt, ohne leere und doppelte
    /// (Groß/klein egal), ohne abschließenden Trenner.</summary>
    class function ParseFolders(const AText: string): TArray<string>; static;
    /// <summary>Liste wieder als Text („;“ getrennt).</summary>
    class function FoldersText(const AFolders: TArray<string>): string; static;
    /// <summary>Ordner dazunehmen (Projektordner); doppelte entfallen.</summary>
    procedure AddFolder(const AFolder: string);
    /// <summary>Liegt APath (vollständiger Pfad) unter einem der Ordner? '' ist nie eigener Code.</summary>
    function IsOwnFile(const APath: string): Boolean;
    /// <summary>Index des ersten eigenen Rahmens; -1 ohne.</summary>
    class function FirstOwn(const AFrames: TAtlasDebugFrames): Integer; static;
    /// <summary>Rahmen für den Ort im Exception-Verlauf: mit AJustMyCode der erste eigene, sonst (und ohne
    /// eigenen) der erste mit Quelltext; -1 ohne.</summary>
    class function LocationIndex(const AFrames: TAtlasDebugFrames; AJustMyCode: Boolean): Integer; static;
    /// <summary>Rahmen, zu dem Atlas nach einer Exception springt; -1 = kein Sprung (aus, kein eigener Rahmen,
    /// oder die IDE zeigt schon eigenen Code).</summary>
    class function JumpIndex(const AFrames: TAtlasDebugFrames; AJustMyCode: Boolean): Integer; static;
    /// <summary>Nach einem Hineinspringen mit „Bis zur Rückkehr“ fortsetzen? AReturns: schon so oft in Folge.
    /// </summary>
    class function ShouldReturn(AJustMyCode, AStepping: Boolean; const AFrames: TAtlasDebugFrames;
      AReturns: Integer): Boolean; static;
    /// <summary>Zeilen der Stapelanzeige. Ohne AJustMyCode jeder Rahmen einzeln und nicht abgeschwächt.
    /// AExpanded: Startindizes aufgeklappter Gruppen.</summary>
    class function Rows(const AFrames: TAtlasDebugFrames; AJustMyCode: Boolean;
      const AExpanded: TArray<Integer>): TAtlasDebugStackRows; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Settings.FolderList;

function NormalFolder(const AFolder: string): string;
begin
  // Wie der Wert der Einstellung (TAtlasFolderList, Base).
  Result := TAtlasFolderList.Normal(AFolder);
end;

function NormalPath(const APath: string): string;
begin
  Result := StringReplace(Trim(APath), '/', '\', [rfReplaceAll]);
end;

function Contains(const AList: TArray<Integer>; AValue: Integer): Boolean;
var
  mItem: Integer;
begin
  for mItem in AList do
  begin
    if mItem = AValue then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function Row(AKind: TAtlasDebugStackRowKind; AFirst, ACount: Integer; AFaded: Boolean): TAtlasDebugStackRow;
begin
  Result.Kind := AKind;
  Result.First := AFirst;
  Result.Count := ACount;
  Result.Faded := AFaded;
end;

{ TAtlasDebugOwnCode }

class function TAtlasDebugOwnCode.Create(const AFolders: TArray<string>): TAtlasDebugOwnCode;
var
  mFolder: string;
begin
  Result.Folders := nil;
  for mFolder in AFolders do
  begin
    Result.AddFolder(mFolder);
  end;
end;

procedure TAtlasDebugOwnCode.AddFolder(const AFolder: string);
var
  mFolder, mKnown: string;
begin
  mFolder := NormalFolder(AFolder);
  if mFolder = '' then
  begin
    Exit;
  end;
  for mKnown in Folders do
  begin
    if SameText(mKnown, mFolder) then
    begin
      Exit;
    end;
  end;
  Folders := Folders + [mFolder];
end;

class function TAtlasDebugOwnCode.ParseFolders(const AText: string): TArray<string>;
begin
  Result := TAtlasFolderList.Parse(AText);
end;

class function TAtlasDebugOwnCode.FoldersText(const AFolders: TArray<string>): string;
begin
  Result := string.Join(';', ParseFolders(string.Join(';', AFolders)));
end;

function TAtlasDebugOwnCode.IsOwnFile(const APath: string): Boolean;
var
  mPath, mFolder: string;
begin
  mPath := NormalPath(APath);
  if mPath = '' then
  begin
    Exit(False);
  end;
  for mFolder in Folders do
  begin
    // Nur ganze Ordner: „C:\Projekt“ umfasst nicht „C:\Projekt2\A.pas“.
    if SameText(Copy(mPath, 1, Length(mFolder) + 1), mFolder + '\') then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasDebugOwnCode.FirstOwn(const AFrames: TAtlasDebugFrames): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AFrames) do
  begin
    if AFrames[mIndex].Own and AFrames[mIndex].HasSource then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

class function TAtlasDebugOwnCode.LocationIndex(const AFrames: TAtlasDebugFrames; AJustMyCode: Boolean): Integer;
begin
  Result := -1;
  if AJustMyCode then
  begin
    Result := FirstOwn(AFrames);
  end;
  if Result < 0 then
  begin
    Result := TAtlasDebugCallStack.FirstWithSource(AFrames);
  end;
end;

class function TAtlasDebugOwnCode.JumpIndex(const AFrames: TAtlasDebugFrames; AJustMyCode: Boolean): Integer;
begin
  Result := -1;
  if not AJustMyCode then
  begin
    Exit;
  end;
  Result := FirstOwn(AFrames);
  // Oberster Rahmen schon eigener Code: Die IDE steht dort.
  if Result = 0 then
  begin
    Result := -1;
  end;
end;

class function TAtlasDebugOwnCode.ShouldReturn(AJustMyCode, AStepping: Boolean; const AFrames: TAtlasDebugFrames;
  AReturns: Integer): Boolean;
begin
  // Ohne Rahmen (Stapel nicht lesbar) nichts tun: lieber die CPU-Ansicht als ein Lauf ins Ungewisse.
  Result := AJustMyCode and AStepping and (AFrames <> nil) and not AFrames[0].HasSource and
    (AReturns < cMaxReturns);
end;

class function TAtlasDebugOwnCode.Rows(const AFrames: TAtlasDebugFrames; AJustMyCode: Boolean;
  const AExpanded: TArray<Integer>): TAtlasDebugStackRows;
var
  mIndex, mStop, mInner: Integer;
begin
  Result := nil;
  mIndex := 0;
  while mIndex <= High(AFrames) do
  begin
    if not AJustMyCode or AFrames[mIndex].Own then
    begin
      Result := Result + [Row(TAtlasDebugStackRowKind.Frame, mIndex, 1, False)];
      Inc(mIndex);
      Continue;
    end;
    mStop := mIndex;
    while (mStop <= High(AFrames)) and not AFrames[mStop].Own do
    begin
      Inc(mStop);
    end;
    if (mStop - mIndex >= cGroupFrom) and not Contains(AExpanded, mIndex) then
    begin
      Result := Result + [Row(TAtlasDebugStackRowKind.LibraryGroup, mIndex, mStop - mIndex, True)];
    end
    else
    begin
      for mInner := mIndex to mStop - 1 do
      begin
        Result := Result + [Row(TAtlasDebugStackRowKind.Frame, mInner, 1, True)];
      end;
    end;
    mIndex := mStop;
  end;
end;

end.
