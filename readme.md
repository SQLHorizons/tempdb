# **Overview**

Enclosed in the repository are the tempdb class and helper functions necessary to make this functional in the exampleScript.ps1

I would imagine the common helper function Connect-SQL used in SqlServerDsc would work, the one included is a slightly different version I use.

The class appears to work well on a new or restarted instance of SQL, but I would expect that if the size of tempdb was attempted to be decreased on an active server, this would initially fail, until the server was rebooted.

I didn't use the concept of 'Ensure Present', because tempdb is always present, I've gone for 'Ensure IsValid'.  The basic of this is if I what it set this way, IsValid is true, and if I wish to no longer enforce these setting IsValid is false.

I was also playing with the idea of dynamically allocating (DynamicAlloc) the number of files, and size based on CPUs and available space on tempdb drive, but as I tend to use mount points in our builds, this started to become more complicated than planed and I needed a MVP for our deployments.
