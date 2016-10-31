 /**
*********************************************************************************
* Copyright Since 2005 ColdBox Platform by Ortus Solutions, Corp
* www.coldbox.org | www.ortussolutions.com
********************************************************************************
* @author Brad Wood, Luis Majano, Denny Valliant
* The CommandBox Shell Object that controls the shell
*/
component accessors="true" singleton {

	// DI
	property name="commandService" 		inject="CommandService";
	property name="readerFactory" 		inject="ReaderFactory";
	property name="print" 				inject="print";
	property name="cr" 					inject="cr@constants";
	property name="formatterUtil" 		inject="Formatter";
	property name="logger" 				inject="logbox:logger:{this}";
	property name="fileSystem"			inject="FileSystem";
	property name="WireBox"				inject="wirebox";
	property name="LogBox"				inject="logbox";
	property name="InterceptorService"	inject="InterceptorService";
	property name="ModuleService"		inject="ModuleService";
	property name="Util"				inject="wirebox.system.core.util.Util";
	

	/**
	* The java jline reader class.
	*/
	property name="reader";
	/**
	* The shell version number
	*/
	property name="version";
	/**
	* The loader version number
	*/
	property name="loaderVersion";
	/**
	* Bit that tells the shell to keep running
	*/
	property name="keepRunning" default="true" type="Boolean";
	/**
	* Bit that is used to reload the shell
	*/
	property name="reloadShell" default="false" type="Boolean";
	/**
	* Clear screen after reload
	*/
	property name="doClearScreen" default="false" type="Boolean";
	/**
	* The Current Working Directory
	*/
	property name="pwd";
	/**
	* The default shell prompt
	*/
	property name="shellPrompt";
	/**
	* This value is either "interactive" meaning the shell stays open waiting for user input
	* or "command" which means a single command will be run and then the shell will be exiting.
	* This differentiation may be useful for commands who want to be careful not to leave threads running
	* that they expect to finish since the JVM will terminiate immedatley after the command finishes.
	* This could also be useful to reduce the amount of extra text that's output such as the CommandBox
	* banner which isn't really needed for a one-off command, especially if the output of that command needs
	* to be fed into another OS command.
	*/
	property name="shellType" default="interactive";
	

	/**
	 * constructor
	 * @inStream.hint input stream if running externally
	 * @outputStream.hint output stream if running externally
	 * @userDir.hint The user directory
	 * @userDir.inject userDir@constants
	 * @tempDir.hint The temp directory
	 * @tempDir.inject tempDir@constants
 	**/
	function init(
		any inStream,
		any outputStream,
		required string userDir,
		required string tempDir,
		boolean asyncLoad=true 
	){

		// Version is stored in cli-build.xml. Build number is generated by Ant.
		// Both are replaced when CommandBox is built.
		variables.version = "@build.version@+@build.number@";
		variables.loaderVersion = "@build.LoaderVersion@";
		// Init variables.
		variables.keepRunning 	= true;
		variables.reloadshell 	= false;
		variables.pwd 			= "";
		variables.reader 		= "";
		variables.shellPrompt 	= "";
		variables.userDir 	 	= arguments.userDir;
		variables.tempDir 		= arguments.tempDir;

		// Save these for onDIComplete()
		variables.initArgs = arguments;

		// If reloading the shell
		if( structKeyExists( request, 'lastCWD' ) ) {
			// Go back where we were
			variables.pwd= request.lastCWD;
		} else {
			// Store incoming current directory
			variables.pwd = variables.userDir;
		}

		setShellType( 'interactive' );

    	return this;
	}

	/**
	 * Finish configuring the shell
	 **/
	function onDIComplete() {
		// Create reader console and setup the default shell Prompt
		variables.reader 		= readerFactory.getInstance( argumentCollection = variables.initArgs  );
		variables.shellPrompt 	= print.green( "CommandBox> ");

		// Create temp dir & set
		setTempDir( variables.tempdir );
		
		getInterceptorService().configure();
		getModuleService().configure();
				
		getModuleService().activateAllModules();
		
		// load commands
		if( variables.initArgs.asyncLoad ){
			thread name="commandbox.loadcommands#getTickCount()#"{
				variables.commandService.configure();
			}
		} else {
			variables.commandService.configure();
		}
	}


	/**
	 * Exists the shell
	 **/
	Shell function exit() {
    	variables.keepRunning = false;

		return this;
	}

	/**
	 * Set's the OS Exit code to be used
	 **/
	Shell function setExitCode( required string exitCode ) {
		createObject( 'java', 'java.lang.System' ).setProperty( 'cfml.cli.exitCode', arguments.exitCode );
		return this;
	}


	/**
	 * Sets reload flag, relaoded from shell.cfm
	 * @clear.hint clears the screen after reload
 	 **/
	Shell function reload( Boolean clear=true ){
		
		setDoClearScreen( arguments.clear );
		setReloadshell( true );
    	setKeepRunning( false );

    	return this;
	}

	/**
	 * Returns the current console text
 	 **/
	string function getText() {
    	return variables.reader.getCursorBuffer().toString();
	}

	/**
	 * Sets the shell prompt
	 * @text.hint prompt text to set, if empty we use the default prompt
 	 **/
	Shell function setPrompt( text="" ) {
		if( !len( arguments.text ) ){
			variables.shellPrompt = print.green( "CommandBox:#listLast( getPWD(), "/\" )#> " );
		} else {
			variables.shellPrompt = arguments.text;
		}
		variables.reader.setPrompt( variables.shellPrompt );
		return this;
	}

	/**
	 * ask the user a question and wait for response
	 * @message.hint message to prompt the user with
	 * @mask.hint When not empty, keyboard input is masked as that character
	 *
	 * @return the response from the user
 	 **/
	string function ask( message, string mask='', string buffer='' ) {
		
		// read reponse while masking input
		var input = variables.reader.readLine(
			// Prompt for the user
			arguments.message,
			// Optionally mask their input
			len( arguments.mask ) ? javacast( "char", left( arguments.mask, 1 ) ) : javacast( "null", '' )//,
			// This won't work until we can upgrade to Jline 2.14
			// Optionally pre-fill a default response for them
		//	len( arguments.buffer ) ? javacast( "String", arguments.buffer ) : javacast( "null", '' )
		);
		
		// Reset back to default prompt
		setPrompt();

		return input;
	}

	/**
	 * Ask the user a question looking for a yes/no response
	 * @message.hint message to prompt the user with
	 *
	 * @return the response from the user as a boolean value
 	 **/
	boolean function confirm( required message ){
		var answer = ask( "#message# : " );
		if( isNull( answer ) ){ return false; }
		if( trim( answer ) == "y" || ( isBoolean( answer ) && answer ) ) {
			return true;
		}
		return false;
	}

	/**
	 * Wait until the user's next keystroke, returns the key pressed
	 * @message.message An optional message to display to the user such as "Press any key to continue."
	 *
	 * @return code of key pressed
 	 **/
	string function waitForKey( message='' ) {
		var key = '';
		if( len( arguments.message ) ) {
			printString( arguments.message );
		}
		key = variables.reader.readCharacter();
		// Reset back to default prompt
		setPrompt();

		return key;
	}

	/**
	 * clears the console
	 *
	 * @note Almost works on Windows, but doesn't clear text background
	 *
 	 **/
	Shell function clearScreen( addLines = true ) {
		// This outputs a double prompt due to the redrawLine() call
		//	reader.clearScreen();

		// A temporary workaround for windows. Since background colors aren't cleared
		// this will force them off the screen with blank lines before clearing.
		if( variables.fileSystem.isWindows() && arguments.addLines ) {
			var i = 0;
			while( ++i <= getTermHeight() + 5 ) {
				variables.reader.println();
			}
		}

		variables.reader.print( '[2J' );
		variables.reader.print( '[1;1H' );

		return this;
	}

	/**
	 * Get's terminal width
  	 **/
	function getTermWidth() {
       	return variables.reader.getTerminal().getWidth();
	}

	/**
	 * Get's terminal height
  	 **/
	function getTermHeight() {
       	return variables.reader.getTerminal().getHeight();
	}

	/**
	 * Alias to get's current directory or use getPWD()
  	 **/
	function pwd() {
    	return variables.pwd;
	}

	/**
	* Get the temp dir in a safe manner
	*/
	string function getTempDir(){
		lock name="commandbox.tempdir" timeout="10" type="readOnly" throwOnTimeout="true"{
			return variables.tempDir;
		}
	}

	/**
	 * sets and renews temp directory
	 * @directory.hint directory to use
  	 **/
	Shell function setTempDir( required directory ){
        lock name="commandbox.tempdir" timeout="10" type="exclusive" throwOnTimeout="true"{

        	// Delete temp dir
	        var clearTemp = directoryExists( arguments.directory ) ? directoryDelete( arguments.directory, true ) : "";

	        // Re-create it. Try 3 times.
	        var tries = 0;
        	try {
        		tries++;
		        directoryCreate( arguments.directory );
        	} catch (any e) {
        		if( tries <= 3 ) {
					variables.logger.info( 'Error creating temp directory [#arguments.directory#]. Trying again in 500ms.', 'Number of tries: #tries#' );
        			// Wait 500 ms and try again.  OS could be locking the dir
        			sleep( 500 );
        			retry;
        		} else {
					variables.logger.info( 'Error creating temp directory [#arguments.directory#]. Giving up now.', 'Tried #tries# times.' );
        			printError( e );
        		}
        	}

        	// set now that it is created.
        	variables.tempdir = arguments.directory;
        }

    	return this;
	}

	/**
	 * Changes the current directory of the shell and returns the directory set.
	 * @directory.hint directory to CD to.  Please verify it exists before calling.
  	 **/
	String function cd( directory="" ){
		variables.pwd = arguments.directory;
		request.lastCWD = arguments.directory;
		// Update prompt to reflect directory change
		setPrompt();
		return variables.pwd;
	}

	/**
	 * Prints a string to the reader console with auto flush
	 * @string.hint string to print (handles complex objects)
  	 **/
	Shell function printString( required string ){
		if( !isSimpleValue( arguments.string ) ){
			systemOutput( "[COMPLEX VALUE]\n" );
			writedump(var=arguments.string, output="console");
			arguments.string = "";
		}
    	variables.reader.print( arguments.string );
    	variables.reader.flush();

    	return this;
	}

	/**
	 * Runs the shell thread until exit flag is set
	 * @input.hint command line to run if running externally
  	 **/
    Boolean function run( input="", silent=false ) {

		// init reload to false, just in case
        variables.reloadshell = false;

		try{
	        // Get input stream
	        if( arguments.input != "" ){
	        	 arguments.input &= chr(10);
	        	var inStream = createObject( "java", "java.io.ByteArrayInputStream" ).init( arguments.input.getBytes() );
	        	variables.reader.setInput( inStream );
	        }

	        // setup bell enabled + keep running flags
	        variables.reader.setBellEnabled( true );
	        variables.keepRunning = true;

	        var line ="";
	        if( !arguments.silent ) {
				// Set default prompt on reader
				setPrompt();
			}

			// while keep running
	        while( variables.keepRunning ){
	        	// check if running externally
				if( arguments.input != "" ){
					variables.keepRunning = false;
				}
								
				// Shell stops on this line while waiting for user input
		        if( arguments.silent ) {
		        	line = variables.reader.readLine( javacast( "char", ' ' ) );
				} else {
		        	line = variables.reader.readLine();
				}
	        		
	        	// If the standard input isn't avilable, bail.  This happens
	        	// when commands are piped in and we've reached the end of the piped stream
	        	if( !isDefined( 'line' ) ) {
	        		return false;
	        	}

	            // If there's input, try to run it.
				if( len( trim( line ) ) ) { 
					callCommand( command=line, initialCommand=true );
				}

	        } // end while keep running

		} catch( any e ){
			SystemOUtput( e.message & e.detail );
			printError( e );
		}

		return variables.reloadshell;
    }

	/**
	 * Call a command
 	 * @command.hint Either a string containing a text command, or an array of tokens representing the command and parameters. 
 	 * @returnOutput.hint True will return the output of the command as a string, false will send the output to the console.  If command outputs nothing, an empty string will come back.
 	 * @piped.hint Any text being piped into the command.  This will overwrite the first parameter (pushing any positional params back)
 	 * @initialCommand.hint Since commands can recursivley call new commands via this method, this flags the first in the chain so exceptions can bubble all the way back to the beginning.
 	 * In other words, if "foo" calls "bar", which calls "baz" and baz errors, all three commands are scrapped and do not finish execution. 
 	 **/
	function callCommand( 
		required any command,
		returnOutput=false,
		string piped,
		boolean initialCommand=false )  {
		
		// Commands a loaded async in interactive mode, so this is a failsafe to ensure the CommandService
		// is finished.  Especially useful for commands run onCLIStart.  Wait up to 5 seconds.
		var i = 0;
		while( !CommandService.getConfigured() && ++i<50 ) {
			sleep( 100  );
		}
				
		// Flush history buffer to disk. I could do this in the quit command
		// but then I would lose everything if the user just closes the window
		variables.reader.getHistory().flush();
			
		try{
			
			if( isArray( command ) ) {
				if( structKeyExists( arguments, 'piped' ) ) {
					var result = variables.commandService.runCommandTokens( arguments.command, piped );
				} else {
					var result = variables.commandService.runCommandTokens( arguments.command );
				}
			} else {
				var result = variables.commandService.runCommandLine( arguments.command );
			}
		
		// This type of error is recoverable-- like validation error or unresolved command, just a polite message please.
		} catch ( commandException var e) {
			// If this is a nested command, pass the exception along to unwind the entire stack.
			if( !initialCommand ) {
				rethrow;
			} else {
				printError( { message : e.message, detail: e.detail } );
			}
		// Anything else is completely unexpected and means boom booms happened-- full stack please.
		} catch (any e) {
			// If this is a nested command, pass the exception along to unwind the entire stack.
			if( !initialCommand ) {
				rethrow;
			} else {
				printError( e );
			}
		}
		
		// Return the output to the caller to deal with
		if( arguments.returnOutput ) {
			if( isNull( result ) ) {
				return '';
			} else {
				return result;
			}
		}
		
		// We get to output the results ourselves
		if( !isNull( result ) && !isSimpleValue( result ) ){
			if( isArray( result ) ){
				return variables.reader.printColumns( result );
			}
			result = variables.formatterUtil.formatJson( serializeJSON( result ) );
			printString( result );
		} else if( !isNull( result ) && len( result ) ) {
			printString( result );
			// If the command output text that didn't end with a line break one, add one
			var lastChar = mid( result, len( result ), 1 );
			if( ! ( lastChar == chr( 10 ) || lastChar == chr( 13 ) ) ) {
				variables.reader.println();
			}
		}

		return '';
	}

	/**
	 * print an error to the console
	 * @err.hint Error object to print (only message is required)
  	 **/
	Shell function printError( required err ){
		
		setExitCode( 1 );
		
		getInterceptorService().announceInterception( 'onException', { exception=err } );
		
		variables.logger.error( '#arguments.err.message# #arguments.err.detail ?: ''#', arguments.err.stackTrace ?: '' );


		variables.reader.print( variables.print.whiteOnRedLine( 'ERROR (#variables.version#)' ) );
		variables.reader.println();
		variables.reader.print( variables.print.boldRedText( variables.formatterUtil.HTML2ANSI( arguments.err.message ) ) );
		variables.reader.println();

		if( structKeyExists( arguments.err, 'detail' ) ) {
			variables.reader.print( variables.print.boldRedText( variables.formatterUtil.HTML2ANSI( arguments.err.detail ) ) );
			variables.reader.println();
		}
		if( structKeyExists( arguments.err, 'tagcontext' ) ){
			var lines = arrayLen( arguments.err.tagcontext );
			if( lines != 0 ){
				for( var idx=1; idx <= lines; idx++) {
					var tc = arguments.err.tagcontext[ idx ];
					if( len( tc.codeprinthtml ) ){
						if( idx > 1 ) {
							variables.reader.print( print.boldCyanText( "called from " ) );
						}
						variables.reader.print( variables.print.boldCyanText( "#tc.template#: line #tc.line##variables.cr#" ));
						variables.reader.print( variables.print.text( variables.formatterUtil.HTML2ANSI( tc.codeprinthtml ) ) );
					}
				}
			}
		}
		if( structKeyExists( arguments.err, 'stacktrace' ) ) {
			variables.reader.print( arguments.err.stacktrace );
		}

		variables.reader.println();

		return this;
	}

}
