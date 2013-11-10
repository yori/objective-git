//
//  GTBranch.m
//  ObjectiveGitFramework
//
//  Created by Josh Abernathy on 3/3/11.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

#import "GTBranch.h"
#import "GTReference.h"
#import "GTEnumerator.h"
#import "GTRepository.h"
#import "GTCommit.h"
#import "NSError+Git.h"

@implementation GTBranch

#pragma mark -
#pragma mark Class methods

+ (NSString *)localNamePrefix {
	return @"refs/heads/";
}

+ (NSString *)remoteNamePrefix {
	return @"refs/remotes/";
}

#pragma mark -
#pragma mark Lifecycle

+ (instancetype)branchByCreatingBranchNamed:(NSString *)name target:(GTCommit *)commit force:(BOOL)force inRepository:(GTRepository *)repository error:(NSError **)error {
	git_reference *git_ref;
	int gitError = git_branch_create(&git_ref, repository.git_repository, name.UTF8String, commit.git_commit, (force ? 1 : 0));
	if (gitError != GIT_OK) {
		if (error != NULL) *error = [NSError git_errorFor:gitError description:@"Branch creation failed"];
		return nil;
	}

	GTReference *ref = [[GTReference alloc] initWithGitReference:git_ref repository:repository];
	return [[self alloc] initWithReference:ref];
}

+ (instancetype)branchByLookingUpBranchNamed:(NSString *)name inRepository:(GTRepository *)repository error:(NSError **)error {
	git_reference *git_ref;
	// First try local branches
	int gitError = git_branch_lookup(&git_ref, repository.git_repository, name.UTF8String, GIT_BRANCH_LOCAL);
	if (gitError != GIT_OK) {
		int gitError = git_branch_lookup(&git_ref, repository.git_repository, name.UTF8String, GIT_BRANCH_REMOTE);
		if (gitError != GIT_OK) {
			if (error != NULL) *error = [NSError git_errorFor:gitError description:@"Branch lookup failed"];
			return nil;
		}
	}

	GTReference *ref = [[GTReference alloc] initWithGitReference:git_ref repository:repository];
	return [[self alloc] initWithReference:ref];
}

+ (id)branchWithReferenceNamed:(NSString *)referenceName inRepository:(GTRepository *)repo error:(NSError **)error {
	NSParameterAssert(referenceName != nil);
	NSParameterAssert(repo != nil);

	GTReference *ref = [GTReference referenceByLookingUpReferenceNamed:referenceName inRepository:repo error:error];
	if (ref == nil) return nil;

	return [[self alloc] initWithReference:ref];
}

+ (id)branchWithReference:(GTReference *)ref {
	return [[self alloc] initWithReference:ref];
}

// Designated initializer
- (id)initWithReference:(GTReference *)ref {
	NSParameterAssert(ref != nil);

	self = [super init];
	if (self == nil) return nil;

	_reference = ref;

	return self;
}

#pragma mark -
#pragma mark NSObject

- (NSString *)description {
	return [NSString stringWithFormat:@"<%@: %p> name: %@, shortName: %@, sha: %@, remoteName: %@, repository: %@", NSStringFromClass([self class]), self, self.name, self.shortName, self.SHA, self.remoteName, self.repository];
}

- (BOOL)isEqual:(GTBranch *)otherBranch {
	if (otherBranch == self) return YES;
	if (![otherBranch isKindOfClass:self.class]) return NO;

	return [self.name isEqual:otherBranch.name] && [self.SHA isEqual:otherBranch.SHA];
}

- (NSUInteger)hash {
	return self.name.hash ^ self.SHA.hash;
}

#pragma mark -
#pragma mark Properties

- (NSString *)name {
	const char *charName;
	int gitError = git_branch_name(&charName, self.reference.git_reference);
	if (gitError != GIT_OK || charName == NULL) return nil;

	return @(charName);
}

- (NSString *)shortName {
	const char *name;
	int gitError = git_branch_name(&name, self.reference.git_reference);
	if (gitError != GIT_OK) return nil;

	if (self.branchType == GTBranchTypeRemote) {
		// Skip the initial remote name and forward slash.
		name = strchr(name, '/');
		if (name == NULL) return nil;

		name++;
	}

	return @(name);
}

- (NSString *)remoteName {
	if (self.branchType == GTBranchTypeLocal) return nil;

	const char *name;
	int gitError = git_branch_name(&name, self.reference.git_reference);
	if (gitError != GIT_OK) return nil;

	// Find out where the remote name ends.
	const char *end = strchr(name, '/');
	if (end == NULL || end == name) return nil;

	return [[NSString alloc] initWithBytes:name length:end - name encoding:NSUTF8StringEncoding];
}

- (GTRepository *)repository {
	return self.reference.repository;
}

- (NSString *)SHA {
	return self.reference.targetSHA;
}

- (GTBranchType)branchType {
	if (self.reference.remote) {
		return GTBranchTypeRemote;
	} else {
		return GTBranchTypeLocal;
	}
}

#pragma mark -
#pragma mark API

- (GTCommit *)targetCommitAndReturnError:(NSError **)error {
	if (self.SHA == nil) {
		if (error != NULL) *error = GTReference.invalidReferenceError;
		return nil;
	}

	return [self.repository lookupObjectBySHA:self.SHA objectType:GTObjectTypeCommit error:error];
}

- (BOOL)deleteWithError:(NSError **)error {
	int gitError = git_branch_delete(self.reference.git_reference);
	if (gitError != GIT_OK) {
		if(error != NULL) *error = [NSError git_errorFor:gitError description:@"Failed to delete branch %@", self.name];
		return NO;
	}

	return YES;
}

- (GTBranch *)reloadedBranchWithError:(NSError **)error {
	GTReference *reloadedRef = [self.reference reloadedReferenceWithError:error];
	if (reloadedRef == nil) return nil;

	return [[self.class alloc] initWithReference:reloadedRef];
}

- (GTBranch *)trackingBranchWithError:(NSError **)error success:(BOOL *)success {
	if (self.branchType == GTBranchTypeRemote) {
		if (success != NULL) *success = YES;
		return self;
	}

	git_reference *trackingRef = NULL;
	int gitError = git_branch_upstream(&trackingRef, self.reference.git_reference);

	// GIT_ENOTFOUND means no tracking branch found.
	if (gitError == GIT_ENOTFOUND) {
		if (success != NULL) *success = YES;
		return nil;
	}

	if (gitError != GIT_OK) {
		if (success != NULL) *success = NO;
		if (error != NULL) *error = [NSError git_errorFor:gitError description:@"Failed to create reference to tracking branch from %@", self];
		return nil;
	}

	if (trackingRef == NULL) {
		if (success != NULL) *success = NO;
		if (error != NULL) *error = [NSError git_errorFor:gitError description:@"Got a NULL remote ref for %@", self];
		return nil;
	}

	if (success != NULL) *success = YES;

	return [[self class] branchWithReference:[[GTReference alloc] initWithGitReference:trackingRef repository:self.repository]];
}

- (NSUInteger)numberOfCommitsWithError:(NSError **)error {
	GTEnumerator *enumerator = [[GTEnumerator alloc] initWithRepository:self.repository error:error];
	if (enumerator == nil) return NSNotFound;

	if (![enumerator pushSHA:self.SHA error:error]) return NSNotFound;
	return [enumerator countRemainingObjects:error];
}

- (NSArray *)uniqueCommitsRelativeToBranch:(GTBranch *)otherBranch error:(NSError **)error {
	NSParameterAssert(otherBranch != nil);

	GTCommit *mergeBase = [self.repository mergeBaseBetweenFirstOID:self.reference.OID secondOID:otherBranch.reference.OID error:error];
	if (mergeBase == nil) return nil;

	GTEnumerator *enumerator = [[GTEnumerator alloc] initWithRepository:self.repository error:error];
	if (enumerator == nil) return nil;

	[enumerator resetWithOptions:GTEnumeratorOptionsTimeSort];

	BOOL success = [enumerator pushSHA:self.SHA error:error];
	if (!success) return nil;

	success = [enumerator hideSHA:mergeBase.SHA error:error];
	if (!success) return nil;

	return [enumerator allObjectsWithError:error];
}

- (BOOL)calculateAhead:(size_t *)ahead behind:(size_t *)behind relativeTo:(GTBranch *)branch error:(NSError **)error {
	if (branch == nil) {
		*ahead = 0;
		*behind = 0;
		return YES;
	}

	int errorCode = git_graph_ahead_behind(ahead, behind, self.repository.git_repository, branch.reference.git_oid, self.reference.git_oid);
	if (errorCode != GIT_OK && error != NULL) {
		*error = [NSError git_errorFor:errorCode description:@"Failed to calculate ahead/behind count of %@ relative to %@", self, branch];
		return NO;
	}

	return YES;
}

@end
