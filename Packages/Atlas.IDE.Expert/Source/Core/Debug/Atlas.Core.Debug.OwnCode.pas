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
    MaxReturns = 16;
    /// <summary>Ab so vielen Bibliotheksrahmen in Folge fasst die Anzeige zusammen.</summary>
    GroupFrom = 2;
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
  System.SysUtils;

function NormalFolder(const AFolder: string): string;
begin
  Result := Trim(AFolder);
  if Result = '' then
    Exit;
  Result := StringReplace(Result, '/', '\', [rfReplaceAll]);
  while (Length(Result) > 1) and (Result[Length(Result)] = '\') do
    Delete(Result, Length(Result), 1);
end;

function NormalPath(const APath: string): string;
begin
  Result := StringReplace(Trim(APath), '/', '\', [rfReplaceAll]);
end;

function Contains(const AList: TArray<Integer>; AValue: Integer): Boolean;
var
  Item: Integer;
begin
  for Item in AList do
    if Item = AValue then
      Exit(True);
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
  Folder: string;
begin
  Result.Folders := nil;
  for Folder in AFolders do
    Result.AddFolder(Folder);
end;

procedure TAtlasDebugOwnCode.AddFolder(const AFolder: string);
var
  Folder, Known: string;
begin
  Folder := NormalFolder(AFolder);
  if Folder = '' then
    Exit;
  for Known in Folders do
    if SameText(Known, Folder) then
      Exit;
  Folders := Folders + [Folder];
end;

class function TAtlasDebugOwnCode.ParseFolders(const AText: string): TArray<string>;
var
  Parts: TArray<string>;
  Part: string;
  List: TAtlasDebugOwnCode;
begin
  List.Folders := nil;
  Parts := StringReplace(StringReplace(AText, #13, ';', [rfReplaceAll]), #10, ';', [rfReplaceAll]).Split([';']);
  for Part in Parts do
    List.AddFolder(Part);
  Result := List.Folders;
end;

class function TAtlasDebugOwnCode.FoldersText(const AFolders: TArray<string>): string;
begin
  Result := string.Join(';', ParseFolders(string.Join(';', AFolders)));
end;

function TAtlasDebugOwnCode.IsOwnFile(const APath: string): Boolean;
var
  Path, Folder: string;
begin
  Path := NormalPath(APath);
  if Path = '' then
    Exit(False);
  for Folder in Folders do
    // Nur ganze Ordner: „C:\Projekt“ umfasst nicht „C:\Projekt2\A.pas“.
    if SameText(Copy(Path, 1, Length(Folder) + 1), Folder + '\') then
      Exit(True);
  Result := False;
end;

class function TAtlasDebugOwnCode.FirstOwn(const AFrames: TAtlasDebugFrames): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(AFrames) do
    if AFrames[Index].Own and AFrames[Index].HasSource then
      Exit(Index);
  Result := -1;
end;

class function TAtlasDebugOwnCode.LocationIndex(const AFrames: TAtlasDebugFrames; AJustMyCode: Boolean): Integer;
begin
  Result := -1;
  if AJustMyCode then
    Result := FirstOwn(AFrames);
  if Result < 0 then
    Result := TAtlasDebugCallStack.FirstWithSource(AFrames);
end;

class function TAtlasDebugOwnCode.JumpIndex(const AFrames: TAtlasDebugFrames; AJustMyCode: Boolean): Integer;
begin
  Result := -1;
  if not AJustMyCode then
    Exit;
  Result := FirstOwn(AFrames);
  // Oberster Rahmen schon eigener Code: Die IDE steht dort.
  if Result = 0 then
    Result := -1;
end;

class function TAtlasDebugOwnCode.ShouldReturn(AJustMyCode, AStepping: Boolean; const AFrames: TAtlasDebugFrames;
  AReturns: Integer): Boolean;
begin
  // Ohne Rahmen (Stapel nicht lesbar) nichts tun: lieber die CPU-Ansicht als ein Lauf ins Ungewisse.
  Result := AJustMyCode and AStepping and (AFrames <> nil) and not AFrames[0].HasSource and
    (AReturns < MaxReturns);
end;

class function TAtlasDebugOwnCode.Rows(const AFrames: TAtlasDebugFrames; AJustMyCode: Boolean;
  const AExpanded: TArray<Integer>): TAtlasDebugStackRows;
var
  Index, Stop, Inner: Integer;
begin
  Result := nil;
  Index := 0;
  while Index <= High(AFrames) do
  begin
    if not AJustMyCode or AFrames[Index].Own then
    begin
      Result := Result + [Row(TAtlasDebugStackRowKind.Frame, Index, 1, False)];
      Inc(Index);
      Continue;
    end;
    Stop := Index;
    while (Stop <= High(AFrames)) and not AFrames[Stop].Own do
      Inc(Stop);
    if (Stop - Index >= GroupFrom) and not Contains(AExpanded, Index) then
      Result := Result + [Row(TAtlasDebugStackRowKind.LibraryGroup, Index, Stop - Index, True)]
    else
      for Inner := Index to Stop - 1 do
        Result := Result + [Row(TAtlasDebugStackRowKind.Frame, Inner, 1, True)];
    Index := Stop;
  end;
end;

end.
