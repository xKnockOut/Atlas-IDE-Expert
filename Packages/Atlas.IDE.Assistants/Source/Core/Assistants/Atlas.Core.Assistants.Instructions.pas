unit Atlas.Core.Assistants.Instructions;

// Anweisungsdateien für KI-Assistenten (#2615), Kern des Plugins ohne VCL: Argumente und Antwort des Serverbefehls
// atlas.server.assistantInstructions und der Vergleich alt/neu für die Meldungsansicht. Den Abschnitt erzeugt und
// schreibt der Server (Atlas.Common.Lsp.Instructions); das Plugin baut keinen zweiten Text.

interface

uses
  System.SysUtils,
  System.JSON;

type
  /// <summary>Eine Datei aus der Antwort: Name wie in atlas.json, Stand vor dem Lauf (current, stale, missing),
  /// alter und neuer Abschnitt, ob geschrieben, Grund eines Fehlschlags.</summary>
  TAtlasInstructionsFile = record
    FileName: string;
    State: string;
    OldSection: string;
    NewSection: string;
    Written: Boolean;
    Error: string;
    /// <summary>Ist der Abschnitt nach dem Lauf nicht aktuell?</summary>
    function Outdated: Boolean;
  end;

  TAtlasInstructions = class
  public const
    cCommand = 'atlas.server.assistantInstructions';
    cConfigFileName = 'atlas.json';
  public
    /// <summary>Argumente: [{"uri": AUri, "write": AWrite}]; AUri wählt den Arbeitsbereich ('' = der einzige).
    /// </summary>
    class function Arguments(const AUri: string; AWrite: Boolean): string; static;
    /// <summary>Dateien aus der Antwort; nil ohne Antwort.</summary>
    class function Parse(const AAnswer: TJSONValue): TArray<TAtlasInstructionsFile>; static;
    /// <summary>Unterschied zweier Abschnitte als Zeilen „- alt“ bzw. „+ neu“ in der Reihenfolge des Textes
    /// (längste gemeinsame Teilfolge der Zeilen); gleiche Zeilen fehlen.</summary>
    class function Diff(const AOld, ANew: string): TArray<string>; static;
    /// <summary>Ist AFileName eine atlas.json?</summary>
    class function IsConfigFile(const AFileName: string): Boolean; static;
  end;

implementation

uses
  System.Generics.Collections; // Inline-Funktionen von TJSONArray (H2443)

{ TAtlasInstructionsFile }

function TAtlasInstructionsFile.Outdated: Boolean;
begin
  Result := (State <> 'current') and not Written;
end;

{ TAtlasInstructions }

class function TAtlasInstructions.Arguments(const AUri: string; AWrite: Boolean): string;
var
  mRoot: TJSONArray;
  mArguments: TJSONObject;
begin
  mRoot := TJSONArray.Create;
  try
    mArguments := TJSONObject.Create;
    mRoot.AddElement(mArguments);
    mArguments.AddPair('uri', AUri);
    mArguments.AddPair('write', TJSONBool.Create(AWrite));
    Result := mRoot.ToJSON([]);
  finally
    mRoot.Free;
  end;
end;

function FileOf(const AItem: TJSONObject): TAtlasInstructionsFile;
begin
  Result := Default(TAtlasInstructionsFile);
  Result.FileName := AItem.GetValue<string>('file', '');
  Result.State := AItem.GetValue<string>('state', '');
  Result.OldSection := AItem.GetValue<string>('old', '');
  Result.NewSection := AItem.GetValue<string>('new', '');
  Result.Written := AItem.GetValue<Boolean>('written', False);
  Result.Error := AItem.GetValue<string>('error', '');
end;

class function TAtlasInstructions.Parse(const AAnswer: TJSONValue): TArray<TAtlasInstructionsFile>;
var
  mFiles: TJSONArray;
  mIndex: Integer;
begin
  Result := nil;
  if not (AAnswer is TJSONObject) or not (TJSONObject(AAnswer).GetValue('files') is TJSONArray) then
  begin
    Exit;
  end;
  mFiles := TJSONArray(TJSONObject(AAnswer).GetValue('files'));
  for mIndex := 0 to mFiles.Count - 1 do
  begin
    if mFiles.Items[mIndex] is TJSONObject then
    begin
      Result := Result + [FileOf(TJSONObject(mFiles.Items[mIndex]))];
    end;
  end;
end;

/// <summary>Zeilen von AText; '' ergibt keine Zeile.</summary>
function LinesOf(const AText: string): TArray<string>;
begin
  Result := nil;
  if AText <> '' then
  begin
    Result := StringReplace(AText, #13#10, #10, [rfReplaceAll]).Split([#10]);
  end;
end;

/// <summary>Länge der längsten gemeinsamen Teilfolge ab AOld[I], ANew[J], je Paar (I, J).</summary>
function CommonLengths(const AOld, ANew: TArray<string>): TArray<TArray<Integer>>;
var
  mI, mJ: Integer;
begin
  Result := nil;
  SetLength(Result, Length(AOld) + 1, Length(ANew) + 1);
  for mI := High(AOld) downto 0 do
  begin
    for mJ := High(ANew) downto 0 do
    begin
      if AOld[mI] = ANew[mJ] then
      begin
        Result[mI][mJ] := Result[mI + 1][mJ + 1] + 1;
      end
      else
      begin
        Result[mI][mJ] := Result[mI + 1][mJ];
        if Result[mI][mJ + 1] > Result[mI][mJ] then
        begin
          Result[mI][mJ] := Result[mI][mJ + 1];
        end;
      end;
    end;
  end;
end;

class function TAtlasInstructions.Diff(const AOld, ANew: string): TArray<string>;
var
  mOld, mNew: TArray<string>;
  mLengths: TArray<TArray<Integer>>;
  mI, mJ: Integer;
begin
  Result := nil;
  mOld := LinesOf(AOld);
  mNew := LinesOf(ANew);
  mLengths := CommonLengths(mOld, mNew);
  mI := 0;
  mJ := 0;
  while (mI < Length(mOld)) or (mJ < Length(mNew)) do
  begin
    if (mI < Length(mOld)) and (mJ < Length(mNew)) and (mOld[mI] = mNew[mJ]) then
    begin
      Inc(mI);
      Inc(mJ);
    end
    else if (mJ >= Length(mNew)) or ((mI < Length(mOld)) and (mLengths[mI + 1][mJ] >= mLengths[mI][mJ + 1])) then
    begin
      Result := Result + ['- ' + mOld[mI]];
      Inc(mI);
    end
    else
    begin
      Result := Result + ['+ ' + mNew[mJ]];
      Inc(mJ);
    end;
  end;
end;

class function TAtlasInstructions.IsConfigFile(const AFileName: string): Boolean;
begin
  Result := SameText(ExtractFileName(StringReplace(StringReplace(AFileName, '/', PathDelim, [rfReplaceAll]), '\',
    PathDelim, [rfReplaceAll])), cConfigFileName);
end;

end.
