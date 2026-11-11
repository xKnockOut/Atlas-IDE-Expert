unit Atlas.Common.Semantics.ExpressionTypes.RecordSizes;

// SizeOf von Records derselben Unit für den Typ eines Ausdrucks (#689): Felder fester Größe, Ausrichtung wie {$A8}
// bzw. packed. Variantenteile und Felder unbekannter Größe ergeben keine Größe; geschachtelte Records mit
// Tiefenschranke.

interface

uses
  Atlas.Common.Pascal.SyntaxTree;

type
  /// <summary>Größe und Ausrichtung eines Records beim Aufsummieren seiner Felder (Ausrichtung wie {$A8} bzw.
  /// packed).</summary>
  TRecordLayout = record
    Size: Integer;
    Align: Integer;
    IsPacked: Boolean;
    Failed: Boolean;
    /// <summary>ACount Felder zu je ABytes mit Ausrichtung AAlign anfügen.</summary>
    procedure Add(ABytes, AAlign, ACount: Integer);
    /// <summary>Gesamtgröße mit Auffüllung auf die Ausrichtung; packed ohne.</summary>
    procedure Finish(out ASize, AAlign: Integer);
  end;

  /// <summary>SizeOf von Records derselben Unit mit Feldern fester Größe; Tiefe gegen Rekursion.</summary>
  TRecordSizes = class
  private
    FTree: TSyntaxTree;
    FDepth: Integer;
    procedure AddFields(AParent: TSyntaxNode; var ALayout: TRecordLayout);
    procedure AddField(AField: TSyntaxNode; var ALayout: TRecordLayout);
    function FieldSize(const ATypeText: string; out ASize, AAlign: Integer): Boolean;
  public
    /// <summary>ADepth: Rekursionstiefe, ab der gezählt wird (Grenze 64).</summary>
    constructor Create(ATree: TSyntaxTree; ADepth: Integer);
    /// <summary>Größe und Ausrichtung des Records ATypeName aus ATree; False ohne Deklaration, mit Variantenteil
    /// oder mit einem Feld unbekannter Größe.</summary>
    function RecordSize(const ATypeName: string; out ASize, AAlign: Integer): Boolean;
    /// <summary>SizeOf des Records ATypeName; ADepth ist die bisherige Rekursionstiefe des Aufrufers.</summary>
    class function Measure(ATree: TSyntaxTree; ADepth: Integer; const ATypeName: string;
      out ASize: Integer): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Math,
  System.Generics.Collections,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Semantics.OrdinalConstants;

const
  cMaxDepth = 64;

/// <summary>Deklaration "ATypeName = record" im Baum; nil ohne.</summary>
function FindRecord(ARoot: TSyntaxNode; const ATypeName: string): TSyntaxNode;
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  Result := nil;
  if ARoot = nil then
  begin
    Exit;
  end;
  // Iterativ (tiefe Bäume sprengen den Stapel nicht); auch lokale Typen in Routinen zählen.
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ARoot);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if (mNode.Kind = TSyntaxKind.TypeDecl) and SameText(mNode.Name, ATypeName) and
        (mNode.FindChild(TSyntaxKind.RecordType) <> nil) then
      begin
        Exit(mNode);
      end;
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mPending.Push(mNode[mIndex]);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

procedure TRecordLayout.Add(ABytes, AAlign, ACount: Integer);
var
  mAlign, mIndex: Integer;
begin
  mAlign := AAlign;
  if IsPacked then
  begin
    mAlign := 1;
  end;
  for mIndex := 1 to ACount do
  begin
    if (mAlign > 1) and (Size mod mAlign <> 0) then
    begin
      Inc(Size, mAlign - Size mod mAlign);
    end;
    Inc(Size, ABytes);
    Align := Max(Align, mAlign);
  end;
end;

procedure TRecordLayout.Finish(out ASize, AAlign: Integer);
begin
  if not IsPacked and (Size mod Align <> 0) then
  begin
    Inc(Size, Align - Size mod Align);
  end;
  ASize := Size;
  AAlign := Align;
  if IsPacked then
  begin
    AAlign := 1;
  end;
end;

/// <summary>packed record: das Token vor record.</summary>
function IsPackedRecord(const ATokens: TArray<TPascalToken>; ABody: TSyntaxNode): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  for mIndex := 1 to High(ATokens) do
  begin
    if (ATokens[mIndex].Offset >= ABody.StartOffset) and ATokens[mIndex].IsKeyword('record') then
    begin
      Result := ATokens[mIndex - 1].IsKeyword('packed');
      Break;
    end;
  end;
end;

constructor TRecordSizes.Create(ATree: TSyntaxTree; ADepth: Integer);
begin
  inherited Create;
  FTree := ATree;
  FDepth := ADepth;
end;

procedure TRecordSizes.AddFields(AParent: TSyntaxNode; var ALayout: TRecordLayout);
var
  mIndex: Integer;
begin
  mIndex := 0;
  while (mIndex < AParent.ChildCount) and not ALayout.Failed do
  begin
    case AParent[mIndex].Kind of
      TSyntaxKind.Visibility:
        AddFields(AParent[mIndex], ALayout);
      TSyntaxKind.Field:
        AddField(AParent[mIndex], ALayout);
      TSyntaxKind.VariantPart:
        ALayout.Failed := True;
    else
      // Übrige Arten: nichts zu tun.
    end;
    Inc(mIndex);
  end;
end;

procedure TRecordSizes.AddField(AField: TSyntaxNode; var ALayout: TRecordLayout);
var
  mTypeRef: TSyntaxNode;
  mBytes, mAlign: Integer;
  mSized: Boolean;
begin
  mBytes := 0;
  mAlign := 1;
  mTypeRef := AField.FindChild(TSyntaxKind.TypeReference);
  mSized := (mTypeRef <> nil) and (FDepth <= cMaxDepth);
  if mSized then
  begin
    Inc(FDepth);
    try
      mSized := FieldSize(TIndexExtractor.TypeText(mTypeRef), mBytes, mAlign);
    finally
      Dec(FDepth);
    end;
  end;
  if mSized then
  begin
    ALayout.Add(mBytes, mAlign, Length(AField.Name.Split([','])));
  end
  else
  begin
    ALayout.Failed := True;
  end;
end;

function TRecordSizes.FieldSize(const ATypeText: string; out ASize, AAlign: Integer): Boolean;
var
  mLowest, mHighest: Int64;
  mHighKnown: Boolean;
  mName: string;
begin
  Result := True;
  mName := Trim(ATypeText);
  if MatchText(mName, ['Double', 'Int64', 'UInt64', 'Currency', 'Comp']) then
  begin
    ASize := 8;
    AAlign := 8;
  end
  else if SameText(mName, 'Single') then
  begin
    ASize := 4;
    AAlign := 4;
  end
  else if TOrdinalConstants.FixedType(mName, mLowest, mHighest, mHighKnown, ASize) then
  begin
    AAlign := ASize;
  end
  else
  begin
    Result := RecordSize(mName, ASize, AAlign);
  end;
end;

function TRecordSizes.RecordSize(const ATypeName: string; out ASize, AAlign: Integer): Boolean;
var
  mDecl, mBody: TSyntaxNode;
  mLayout: TRecordLayout;
begin
  Result := False;
  ASize := 0;
  AAlign := 1;
  mDecl := FindRecord(FTree.Root, ATypeName);
  if mDecl = nil then
  begin
    Exit;
  end;
  mBody := mDecl.FindChild(TSyntaxKind.RecordType);
  mLayout := Default(TRecordLayout);
  mLayout.Align := 1;
  mLayout.IsPacked := IsPackedRecord(FTree.Tokens, mBody);
  AddFields(mBody, mLayout);
  Result := not mLayout.Failed and (mLayout.Size > 0);
  if Result then
  begin
    mLayout.Finish(ASize, AAlign);
  end;
end;

class function TRecordSizes.Measure(ATree: TSyntaxTree; ADepth: Integer; const ATypeName: string;
  out ASize: Integer): Boolean;
var
  mSizes: TRecordSizes;
  mAlign: Integer;
begin
  mSizes := TRecordSizes.Create(ATree, ADepth);
  try
    Result := mSizes.RecordSize(ATypeName, ASize, mAlign);
  finally
    mSizes.Free;
  end;
end;

end.
