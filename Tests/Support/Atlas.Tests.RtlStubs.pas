unit Atlas.Tests.RtlStubs;

// Testhilfe: kleine Stubs der RTL für Prüfungen mit Symbolindex (#1106, #1112):
// System, System.Classes, System.Contnrs und System.Generics.Collections mit
// den Typen, die die Regeln für Listen, Stapel und Warteschlangen auflösen.
// Gemeinsam für die Regeltests und den Golden-Korpus mit Index.

interface

uses
  Atlas.Common.Index.Contract;

type
  TRtlStubs = record
  public
    /// <summary>Legt die Stub-Units in AIndex an (Pfade unter C:\BDS\source).</summary>
    class procedure AddTo(const AIndex: ISymbolIndex); static;
  end;

implementation

uses
  Atlas.Common.Index.Extractor;

class procedure TRtlStubs.AddTo(const AIndex: ISymbolIndex);
begin
  AIndex.AddUnit(TIndexExtractor.ExtractText('unit System;'#10'interface'#10'type'#10'  TObject = class'#10 +
    '  end;'#10'implementation'#10'end.', 'C:\BDS\source\System.pas', nil));
  AIndex.AddUnit(TIndexExtractor.ExtractText('unit System.Classes;'#10'interface'#10'type'#10 +
    '  TList = class(TObject)'#10'  protected'#10'    function Get(Index: Integer): Pointer;'#10 +
    '  public'#10'    function Add(Item: Pointer): Integer;'#10'    function First: Pointer;'#10 +
    '    function Last: Pointer;'#10'    function Extract(Item: Pointer): Pointer;'#10 +
    '    property Count: Integer read FCount;'#10 +
    '    property Items[Index: Integer]: Pointer read Get; default;'#10'  end;'#10 +
    '  TStrings = class(TObject)'#10'  public'#10 +
    '    property Objects[Index: Integer]: TObject read GetObject;'#10'  end;'#10 +
    'implementation'#10'end.', 'C:\BDS\source\System.Classes.pas', nil));
  AIndex.AddUnit(TIndexExtractor.ExtractText('unit System.Contnrs;'#10'interface'#10'uses'#10'  System.Classes;'#10 +
    'type'#10'  TObjectList = class(TList)'#10'  protected'#10'    function GetItem(Index: Integer): TObject;'#10 +
    '  public'#10'    function First: TObject;'#10'    function Last: TObject;'#10 +
    '    property Items[Index: Integer]: TObject read GetItem; default;'#10'  end;'#10 +
    '  TOrderedList = class(TObject)'#10'  public'#10'    function Count: Integer;'#10 +
    '    function AtLeast(ACount: Integer): Boolean;'#10 +
    '    function Push(AItem: Pointer): Pointer;'#10'    function Pop: Pointer;'#10'    function Peek: Pointer;'#10 +
    '  end;'#10'  TStack = class(TOrderedList)'#10'  end;'#10'  TQueue = class(TOrderedList)'#10'  end;'#10 +
    '  TObjectStack = class(TStack)'#10'  public'#10'    function Push(AObject: TObject): TObject;'#10 +
    '    function Pop: TObject;'#10'    function Peek: TObject;'#10'  end;'#10 +
    '  TObjectQueue = class(TQueue)'#10'  public'#10'    function Push(AObject: TObject): TObject;'#10 +
    '    function Pop: TObject;'#10'    function Peek: TObject;'#10'  end;'#10 +
    'implementation'#10'end.', 'C:\BDS\source\System.Contnrs.pas', nil));
  AIndex.AddUnit(TIndexExtractor.ExtractText('unit System.Generics.Collections;'#10'interface'#10'type'#10 +
    '  TList<T> = class(TObject)'#10'  protected'#10'    function GetItem(Index: Integer): T;'#10'  public'#10 +
    '    function First: T;'#10'    property Items[Index: Integer]: T read GetItem; default;'#10'  end;'#10 +
    '  TObjectList<T: class> = class(TList<T>)'#10'  end;'#10 +
    '  TStack<T> = class(TObject)'#10'  public'#10'    function Pop: T;'#10'    function Peek: T;'#10 +
    '    function Extract: T;'#10'  end;'#10'  TQueue<T> = class(TObject)'#10'  public'#10 +
    '    function Dequeue: T;'#10'    function Peek: T;'#10'    function Extract: T;'#10'  end;'#10 +
    '  TObjectStack<T: class> = class(TStack<T>)'#10'  end;'#10'  TObjectQueue<T: class> = class(TQueue<T>)'#10 +
    '  end;'#10 +
    'implementation'#10'end.', 'C:\BDS\source\System.Generics.Collections.pas', nil));
end;

end.
