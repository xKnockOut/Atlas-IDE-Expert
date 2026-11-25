unit Atlas.Common.Pascal.TreeHandles;

// Syntaxbaum als Handle für Schnittstellen zwischen Features (IPascalSyntaxTree im Pascal-Contract): Wrap macht
// aus einem Baum einen Handle, TreeOf holt den Baum zurück. Der Handle besitzt den Baum nicht; wer ihn weitergibt,
// hält den Baum am Leben, solange der Handle benutzt wird.

interface

uses
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree;

type
  TSyntaxTreeHandles = record
    /// <summary>Handle für ATree; nil ohne Baum.</summary>
    class function Wrap(ATree: TSyntaxTree): IPascalSyntaxTree; static;
    /// <summary>Baum hinter AHandle; nil ohne Handle oder bei einem Handle, den nicht Wrap angelegt hat.</summary>
    class function TreeOf(const AHandle: IPascalSyntaxTree): TSyntaxTree; static;
  end;

implementation

uses
  System.SysUtils;

type
  /// <summary>Zugriff auf den Baum, nur innerhalb von Pascal.</summary>
  ISyntaxTreeAccess = interface
    ['{07CFAA6A-5DAD-43B4-B8DD-FDD4294C914C}']
    function Tree: TSyntaxTree;
  end;

  TSyntaxTreeHandle = class(TInterfacedObject, IPascalSyntaxTree, ISyntaxTreeAccess)
  private
    FTree: TSyntaxTree;
  public
    constructor Create(ATree: TSyntaxTree);
    function Tree: TSyntaxTree;
  end;

{ TSyntaxTreeHandle }

constructor TSyntaxTreeHandle.Create(ATree: TSyntaxTree);
begin
  inherited Create;
  FTree := ATree;
end;

function TSyntaxTreeHandle.Tree: TSyntaxTree;
begin
  Result := FTree;
end;

{ TSyntaxTreeHandles }

class function TSyntaxTreeHandles.Wrap(ATree: TSyntaxTree): IPascalSyntaxTree;
begin
  Result := nil;
  if ATree <> nil then
  begin
    Result := TSyntaxTreeHandle.Create(ATree);
  end;
end;

class function TSyntaxTreeHandles.TreeOf(const AHandle: IPascalSyntaxTree): TSyntaxTree;
var
  mAccess: ISyntaxTreeAccess;
begin
  Result := nil;
  if Supports(AHandle, ISyntaxTreeAccess, mAccess) then
  begin
    Result := mAccess.Tree;
  end;
end;

end.
