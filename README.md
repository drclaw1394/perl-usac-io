# NAME

uSAC::SIO - Streamlined non blocking Socket/Pipe/FIFO IO

# SYNOPSIS

```perl
    use uSAC::SIO;

    #Existing file handle my $fh=open_nonblocking_socket_or_pipe_somehow();
    #ctx my $ctx={could_be=>"any user defined scalar/object"};
    
    #Create a new sio object with the nominated context and file handle my
    $sio=uSAC::SIO->new($ctx, $fh);

    #Event accessors are read/write lvalues. Makes for neat and efficient
    code $sio->on_error=sub {}; $sio->on_read=sub {}; $sio->on_eof=sub {};


    #Start reading events $sio->start;
    
    #queuing write with no callback $sio->write("hello world");

    #queuing write with callback $sio->write("hello again", sub { say
    "Write complete" });


    #pause the event hanlding from the fh #Call start to renable events
    $sio->pause;
```

# DESCRIPTION

uSAC::SIO (Streamlined IO) is built around perl features (some experimental
currently) and AnyEvent to give efficient and easy to use reading and writing
of non blocking file handles.

uSAC::SIO isn't really intended to be used as a stand alone do-it-all IO
module. It's deliberately designed to delegate to and rely on other
modules/classes. It is a mix and match of object oriented and functional
programming. Trading complete opaqueness for run time performance.

It uses [uSAC::SReader](https://metacpan.org/pod/uSAC%3A%3ASReader) and [uSAC::SWriter](https://metacpan.org/pod/uSAC%3A%3ASWriter) so please refer to those modules
for further details not covered here.

# DESIGN

## Array Backed Object

Using an array instead of a hash reduces memory and element access time. It also
has the benefit of making it a little harder to circumvent the documented API
outside of the `uSAC::SIO` package.

It can be extended with a couple lines of code in case your really want to add
features.

## Lexical Aliasing

The experimental feature "refaliasing" is utilised to alias object variables
into lexical scope. The idea is to further reduce variable access in code
executing most often.

## Directly Writable Fields (lvalues)

While possibly breaking OO principles, accessors to writable class elements are
lvalues. Cleaner and less code to write.

```perl
    eg $sio->on_read=sub{};
```

The logic here is to change the critical callback path for read events. For
example to change a parser processing read events on the fly.

## Non Destructive Write Buffering with Optional Callbacks

The data to write is aliased (not a reference or copied) into a write queue if
the data cannot be immediately be written. An offset and the optionally
supplied callback are also queued.

When the complete data for write call is eventually written, the callback is
called. Because the write position is remembered with an offset, no extra data
copies in 'shifting' the buffer are required. It also means there are no copies
in the queue to begin with

```perl
    eg $sio->write("some data to write", sub {});

    
```

## Delegated Timing

Rather than using a timer for every object to monitor, references to variables
outside the object are used as a clock source and sample store. 

This allows a shared single timer running at 'large' intervals to be used to
update the clock variable.

Timeout logic is delegated to external code, keeping the IO subroutines concise
an efficient.

Usually the exact time of a timeout isn't that critical, as long as it has one.

# API

## Constructors

### `new`

```
    uSAC::SIO->new($ctx, $fh);
```

Creates a new `uSAC::SIO` instance.

`$ctx` is required but can be `undef`. It is passed to callback functions and
is defined by the user.

`$fh` is a file handle already opened and will be setup for non blocking operation. It
is assumed to be both readable and writable. 

Event watcher for read and write events are setup (via [uSAC::SReader](https://metacpan.org/pod/uSAC%3A%3ASReader) and
[uSAC::SWriter](https://metacpan.org/pod/uSAC%3A%3ASWriter)

## Stream IO

### `start`

```
    $sio->start;
```

Sets up read event watcher to call `on_read` callback when data is available

### `write`

```
    $sio->write($data,$cb, $arg);
```

Attempt to write data immediately. If successful, the callback is called with
the argument

If the only partial data could be written, the callback and data offset is
stored in a write queue.

At this point a writable watcher is created to service the queue whenever the
queue has data remaining.

If another write call is issued while a write watcher is active, the data is
queued.

Data is aliased to prevent copying of data. Do not change the data until the
callback has been called.

### pause

```perl
    $sio->pause;
```

Stops watching for read and write events. Any data in write queue will not be
processed until another write call is issued

### timimg

```perl
    my ($read_sample,$write_sample,$clock);
    $sio->timing(\$read_sample, \$write_sample, \$clock);
```

Sets the references to variables to use as a clock and to store a sample of the
clock when read and write events occur.

Every time a `sysread` is about to be called, the value or `$clock` is
sampled and stored in `$read_sample`.

In a similar fashion, each time `syswrite` is about to be called, `$clock` is
sampled and stored in `$write_sample`.

## Accessors

### writer

```perl
    my $wr=$sio->writer;
```

Read only

Returns the anonymous sub  which actually performs the writing under the hood
of a `write` call. The writer is created if it doesn't already exist.

Use this directly if you want to avoid the OO interface for a little more
throughput

### ctx

```perl
    my $ctx=$sio->ctx;              #read $sio->ctx="value";
    #write
```

Read/Write

Returns the ctx shared for the reader and the writer. The `ctx` is used as the
first argument to the event callbacks.

To set a new value of ctx, use it as an lvalue

### fh

```perl
    my $fh=$sio->fh;                #return filehandle 
```

Read only

Returns the file handle

### on\_error

```perl
    my $e=$sio->on_error;           #return current on_error handler
    $sio->on_error=sub {};          #Assign new on_error handler
```

Read/Write

Returns the current on\_error handler

### on\_read

```perl
    my $e=$sio->on_read;            #return current on_read handler
    $sio->on_read=sub {};           #Assign new on_read handler
```

Read/Write

Returns the current on\_read handler

### on\_eof

```perl
    my $e=$sio->on_eof;             #return current on_eof handler
    $sio->on_eof=sub {};            #Assign new on_eof handler
```

Read/Write

Returns the current on\_eof handler

## COOKBOOK

TODO

## PERFORMANCE

TODO

## REPOSITORY

Checkout the repository at 

## AUTHUR

Ruben Westerberg 

## COPYRIGHT

Copyright (C) Ruben Westerberg 2022

# LICENSE

MIT or Perl, whichever you choose.
